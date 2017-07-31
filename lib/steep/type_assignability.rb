module Steep
  class TypeAssignability
    attr_reader :interfaces

    def initialize()
      @interfaces = {}
      @klasses = []
      @instances = []
    end

    def with(klass: nil, instance: nil, &block)
      @klasses.push(klass) if klass
      @instances.push(instance) if instance
      yield
    ensure
      @klasses.pop if klass
      @instances.pop if instance
    end

    def klass
      @klasses.last
    end

    def instance
      @instances.last
    end

    def add_interface(interface)
      interfaces[TypeName::Interface.new(name: interface.name)] = interface
    end

    def test(src:, dest:, known_pairs: [])
      case
      when src.is_a?(Types::Any) || dest.is_a?(Types::Any)
        true
      when src == dest
        true
      when src.is_a?(Types::Union)
        src.types.all? do |type|
          test(src: type, dest: dest, known_pairs: known_pairs)
        end
      when dest.is_a?(Types::Union)
        dest.types.any? do |type|
          test(src: src, dest: type, known_pairs: known_pairs)
        end
      when src.is_a?(Types::Name) && dest.is_a?(Types::Name)
        test_interface(resolve_interface(src.name, src.params), resolve_interface(dest.name, dest.params), known_pairs)
      else
        raise "Unexpected type: src=#{src.inspect}, dest=#{dest.inspect}, known_pairs=#{known_pairs.inspect}"
      end
    end

    def test_application(params:, argument:, index:)
      param_type = params.flat_unnamed_params[index]&.last
      if param_type
        unless test(src: argument, dest: param_type)
          yield param_type
        end
      end
    end

    def test_interface(src, dest, known_pairs)
      if src.name == dest.name
        return true
      end

      if known_pairs.include?([src, dest])
        return true
      end

      pairs = known_pairs + [[src, dest]]

      dest.methods.all? do |name, dest_methods|
        if src.methods.key?(name)
          src_methods = src.methods[name]

          dest_methods.all? do |dest_method|
            src_methods.any? do |src_method|
              test_method(src_method, dest_method, pairs)
            end
          end
        end
      end
    end

    def test_method(src, dest, known_pairs)
      test_params(src.params, dest.params, known_pairs) &&
        test_block(src.block, dest.block, known_pairs) &&
        test(src: src.return_type, dest: dest.return_type, known_pairs: known_pairs)
    end

    def test_params(src, dest, known_pairs)
      assigning_pairs = []

      src_flat = src.flat_unnamed_params
      dest_flat = dest.flat_unnamed_params

      case
      when dest.rest
        return false unless src.rest

        while src_flat.size > 0
          src_type = src_flat.shift
          dest_type = dest_flat.shift

          if dest_type
            assigning_pairs << [src_type.last, dest_type.last]
          else
            assigning_pairs << [src_type.last, dest.rest]
          end
        end

        if src.rest
          assigning_pairs << [src.rest, dest.rest]
        end
      when src.rest
        while src_flat.size > 0
          src_type = src_flat.shift
          dest_type = dest_flat.shift

          if dest_type
            assigning_pairs << [src_type.last, dest_type.last]
          else
            break
          end
        end

        if src.rest && !dest_flat.empty?
          dest_flat.each do |dest_type|
            assigning_pairs << [src.rest, dest_type.last]
          end
        end
      when src.required.size + src.optional.size >= dest.required.size + dest.optional.size && !src.rest
        while src_flat.size > 0
          src_type = src_flat.shift
          dest_type = dest_flat.shift

          if dest_type
            assigning_pairs << [src_type.last, dest_type.last]
          else
            break
          end
        end
      else
        return false
      end

      src_flat_kws = src.flat_keywords
      dest_flat_kws = dest.flat_keywords

      dest_flat_kws.each do |name, _|
        if src_flat_kws.key?(name)
          assigning_pairs << [src_flat_kws[name], dest_flat_kws[name]]
        else
          if src.rest_keywords
            assigning_pairs << [src.rest_keywords, dest_flat_kws[name]]
          else
            return false
          end
        end
      end

      src.required_keywords.each do |name, _|
        unless dest.required_keywords.key?(name)
          return false
        end
      end

      if src.rest_keywords && dest.rest_keywords
        assigning_pairs << [src.rest_keywords, dest.rest_keywords]
      end

      assigning_pairs.all? do |pair|
        src_type = pair.first
        dest_type = pair.last

        test(src: dest_type, dest: src_type, known_pairs: known_pairs)
      end
    end

    def test_block(src, dest, known_pairs)
      true
    end

    def resolve_interface(name, params)
      interfaces[name].to_interface(klass: klass, instance: instance, params: params)
    end

    def method_type(type, name)
      return type if type.is_a?(Types::Any)

      interface = resolve_interface(type.name, type.params)
      method = interface.methods[name]

      if method
        yield(method) || Types::Any.new
      else
        yield(nil) || Types::Any.new
      end
    end
  end
end
