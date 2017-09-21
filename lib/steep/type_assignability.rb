module Steep
  class TypeAssignability
    attr_reader :signatures
    attr_reader :errors

    def initialize()
      @signatures = {}
      @klasses = []
      @instances = []
      @errors = []

      if block_given?
        yield self
        validate
      end
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

    def add_signature(signature)
      raise "Signature Duplicated: #{signature.name}" if signatures.key?(signature.name)
      signatures[signature.name] = signature
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
      when src.is_a?(Types::Var) || dest.is_a?(Types::Var)
        known_pairs.include?([src, dest])
      when src.is_a?(Types::Name) && dest.is_a?(Types::Name)
        test_interface(resolve_interface(src.name, src.params), resolve_interface(dest.name, dest.params), known_pairs)
      when src.is_a?(Types::Tuple) && dest.is_a?(Types::Tuple)
        src.types.zip(dest.types) do |type1, type2|
          test(src: type1, dest: type2, known_pairs: known_pairs)
        end
      when src.is_a?(Types::Name) && dest.is_a?(Types::Tuple)
        params = [dest.types.uniq.size == 1 ? dest.types.first : Types::Any.new]
        test_interface(resolve_interface(src.name, src.params), resolve_interface(TypeName::Instance.new(name: :Array), params), known_pairs)
      when src.is_a?(Types::Tuple) && dest.is_a?(Types::Name)
        params = [src.types.uniq.size == 1 ? src.types.first : Types::Any.new]
        test_interface(resolve_interface(TypeName::Instance.new(name: :Array), params), resolve_interface(dest.name, dest.params), known_pairs)
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
      if src == dest
        return true
      end

      if known_pairs.include?([src, dest])
        return true
      end

      pairs = known_pairs + [[src, dest]]

      dest.methods.all? do |name, dest_methods|
        if src.methods.key?(name)
          src_methods = src.methods[name]

          dest_methods.types.all? do |dest_method|
            src_methods.types.any? do |src_method|
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
      when src.required.size + src.optional.size >= dest.required.size + dest.optional.size
        while src_flat.size > 0
          src_type = src_flat.shift
          dest_type = dest_flat.shift

          if dest_type
            assigning_pairs << [src_type.last, dest_type.last]
          else
            if src_type.first == :required
              return false
            else
              break
            end
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
      return true if !src && !dest
      return false if !src || !dest

      raise "Keyword args for block is not yet supported" unless src.params&.flat_keywords&.empty?
      raise "Keyword args for block is not yet supported" unless dest.params&.flat_keywords&.empty?

      ss = src.params.flat_unnamed_params
      ds = dest.params.flat_unnamed_params

      max = ss.size > ds.size ? ss.size : ds.size

      for i in 0...max
        s = ss[i]&.last || src.params.rest
        d = ds[i]&.last || dest.params.rest

        if s && d
          test(src: s, dest: d, known_pairs: known_pairs) or return false
        end
      end

      if src.params.rest && dest.params.rest
        test(src: src.params.rest, dest: dest.params.rest, known_pairs: known_pairs) or return false
      end

      test(src: dest.return_type, dest: src.return_type, known_pairs: known_pairs)
    end

    def resolve_interface(name, params, klass: nil, instance: nil, constructor: nil)
      klass ||= Types::Name.module(name: name.name, params: params)
      instance ||= Types::Name.instance(name: name.name, params: params)

      case name
      when TypeName::Interface
        signatures[name.name].to_interface(klass: klass, instance: instance, params: params)
      when TypeName::Instance
        methods = signatures[name.name].instance_methods(assignability: self, klass: klass, instance: instance, params: params)
        Interface.new(name: name, params: params, methods: methods.reject {|key, _| key == :initialize })
      when TypeName::Module
        methods = signatures[name.name].module_methods(assignability: self, klass: klass, instance: instance, params: params, constructor: constructor)
        Interface.new(name: name, params: params, methods: methods)
      else
        raise "Unexpected type name: #{name.inspect}"
      end
    end

    def lookup_included_signature(type)
      raise "#{self.class}#lookup_included_signature expects type name: #{type.inspect}" unless type.is_a?(Types::Name)
      raise "#{self.class}#lookup_included_signature expects module instance name: #{type.name.inspect}" unless type.name.is_a?(TypeName::Instance)

      signatures[type.name.name]
    end

    def lookup_super_class_signature(type)
      raise "#{self.class}#lookup_super_class_signature expects type name: #{type.inspect}" unless type.is_a?(Types::Name)
      raise "#{self.class}#lookup_super_class_signature expects module instance name: #{type.name.inspect}" unless type.name.is_a?(TypeName::Instance)

      signature = signatures[type.name.name]

      raise "#{self.class}#lookup_super_class_signature expects class: #{type.name.inspect}" unless signature.is_a?(Signature::Class)

      signature
    end

    def lookup_class_signature(type)
      raise "#{self.class}#lookup_class_signature expects type name: #{type.inspect}" unless type.is_a?(Types::Name)
      raise "#{self.class}#lookup_class_signature expects instance name: #{type.name.inspect}" unless type.name.is_a?(TypeName::Instance)

      signature = signatures[type.name.name]

      raise "#{self.class}#lookup_super_class_signature expects class: #{signature.inspect}" unless signature.is_a?(Signature::Class)

      signature
    end

    def lookup_extensions(module_name)
      signatures.values.select do |signature|
        case signature
        when Signature::Extension
          signature.module_name == module_name
        end
      end
    end

    def method_type(type, name, args: nil)
      case type
      when Types::Any
        return type
      when Types::Merge
        methods = type.types.map {|t|
          resolve_interface(t.name, t.params, klass: Types::Var.new(name: :some_klass), instance: Types::Var.new(name: :some_instance))
        }.each.with_object({}) {|interface, methods|
          methods.merge! interface.methods
        }
        method = methods[name]
      when Types::Name
        constructor = type.name.is_a?(TypeName::Module) && type.name.constructor
        interface = resolve_interface(type.name, type.params, constructor: constructor)
        method = interface.methods[name]
      when Types::Tuple
        method = resolve_tuple_method(name, type.types, args)
        unless method
          types = type.types.uniq
          interface = resolve_interface(TypeName::Instance.new(name: :Array), types.size == 1 ? types : [Types::Any.new])
          method = interface.methods[name]
        end
      else
        raise "Unexpected type: #{type}"
      end

      if method
        yield(method) || Types::Any.new
      else
        yield(nil) || Types::Any.new
      end
    end

    def resolve_tuple_method(name, types, args)
      return unless args
      return unless (name == :[] && args.size == 1) || (name == :[]= && args.size == 2)
      return unless args.first.type == :int
      idx = args.first.children[0]
      return unless 0 <= idx && idx < types.size
      idx_type = types[idx]
      required = [Types::Name.instance(name: :Integer)]
      required << idx_type if name == :[]=
      Interface::Method.new(types: [Interface::MethodType.new(type_params: [],
                                                              params: Steep::Interface::Params.empty.with(required: required),
                                                              block: nil,
                                                              return_type: idx_type)],
                            super_method: nil,
                            attributes: [])
    end

    def validate
      signatures.each do |name, signature|
        signature.validate(self)
      end
    end

    def validate_type_presence(signature, type)
      if type.is_a?(Types::Name)
        unless signatures[type.name.name]
          errors << Signature::Errors::UnknownTypeName.new(signature: signature, type: type)
        end
      end
    end

    def validate_method_compatibility(signature, method_name, method)
      if method.super_method
        test = method.types.all? {|method_type|
          method.super_method.types.any? {|super_type|
            test_method(method_type, super_type, [])
          }
        }

        unless test
          errors << Signature::Errors::IncompatibleOverride.new(signature: signature,
                                                                method_name: method_name,
                                                                this_method: method.types,
                                                                super_method: method.super_method.types)
        end
      end
    end

    def compact(types)
      types = types.reject {|type| type.is_a?(Types::Any) }
      
      if types.empty?
        [Types::Any.new]
      else
        compact0(types)
      end
    end

    def compact0(types)
      if types.size == 1
        types
      else
        type, *types_ = types
        compacted = compact0(types_)
        compacted.flat_map do |type_|
          case
          when type == type_
            [type]
          when test(src: type_, dest: type)
            [type]
          when test(src: type, dest: type_)
            [type_]
          else
            [type, type_]
          end
        end.uniq
      end
    end
  end
end
