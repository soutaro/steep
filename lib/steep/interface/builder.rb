module Steep
  module Interface
    class Builder
      class RecursiveDefinitionError < StandardError
        attr_reader :chain

        def initialize(type_name)
          @chain = [type_name].compact
          super "Recursive inheritance/mixin"
        end

        def to_s
          super + " #{chain.join(" ~> ")}"
        end
      end

      attr_reader :signatures
      attr_reader :cache

      def initialize(signatures:)
        @cache = {}
        @signatures = signatures
      end

      def absolute_type_name(type_name, current:)
        if current
          begin
            case type_name
            when TypeName::Instance
              type_name.map_module_name {|name|
                signatures.find_class_or_module(name, current_module: current).name
              }
            when TypeName::Module
              type_name.map_module_name {|name|
                signatures.find_module(name, current_module: current).name
              }
            when TypeName::Class
              type_name.map_module_name {|name|
                signatures.find_class(name, current_module: current).name
              }
            else
              type_name
            end
          rescue => exn
            STDERR.puts "Cannot find absolute type name: #{exn.inspect}"
            type_name
          end
        else
          type_name.map_module_name(&:absolute!)
        end
      end

      def absolute_type(type, current:)
        case type
        when AST::Types::Name
          AST::Types::Name.new(
            name: absolute_type_name(type.name, current: current),
            args: type.args.map {|ty| absolute_type(ty, current: current) },
            location: type.location
          )
        when AST::Types::Union
          AST::Types::Union.build(
            types: type.types.map {|ty| absolute_type(ty, current: current) },
            location: type.location
          )
        when AST::Types::Intersection
          AST::Types::Intersection.build(
            types: type.types.map {|ty| absolute_type(ty, current: current) },
            location: type.location
          )
        when AST::Types::Tuple
          AST::Types::Tuple.new(
            types: type.types.map {|ty| absolute_type(ty, current:current) },
            location: type.location
          )
        else
          type
        end
      end

      def build(type_name, current: nil, with_initialize: false)
        type_name = absolute_type_name(type_name, current: current)
        cache_key = [type_name, with_initialize]
        cached = cache[cache_key]

        case cached
        when nil
          begin
            cache[cache_key] = type_name

            interface = case type_name
                        when TypeName::Instance
                          instance_to_interface(signatures.find_class_or_module(type_name.name), with_initialize: with_initialize)
                        when TypeName::Module
                          module_to_interface(signatures.find_module(type_name.name))
                        when TypeName::Class
                          class_to_interface(signatures.find_class_or_module(type_name.name),
                                             constructor: type_name.constructor)
                        when TypeName::Interface
                          interface_to_interface(type_name.name,
                                                 signatures.find_interface(type_name.name))
                        else
                          raise "Unexpected type_name: #{type_name.inspect}"
                        end

            cache[cache_key]= interface
          rescue RecursiveDefinitionError => exn
            exn.chain.unshift(type_name)
            raise
          end
        when TypeName::Base
          raise RecursiveDefinitionError, type_name
        else
          cached
        end
      end

      def merge_mixin(type_name, args, methods:, ivars:, supers:, current:)
        mixed = block_given? ? yield : build(type_name, current: current)

        supers.push(*mixed.supers)
        instantiated = mixed.instantiate(
          type: AST::Types::Self.new,
          args: args,
          instance_type: AST::Types::Instance.new,
          module_type: AST::Types::Class.new
        )

        methods.merge!(instantiated.methods) do |_, super_method, new_method|
          if super_method.include_in_chain?(new_method)
            super_method
          else
            new_method.with_super(super_method)
          end
        end

        merge_ivars ivars, instantiated.ivars
      end

      def add_method(type_name, method, methods:)
        super_method = methods[method.name]
        new_method = Method.new(
          type_name: type_name,
          name: method.name,
          types: method.types.map do |method_type|
            method_type_to_method_type(method_type, current: type_name.name)
          end,
          super_method: super_method,
          attributes: method.attributes
        )

        methods[method.name] = if super_method&.include_in_chain?(new_method)
                                 super_method
                               else
                                 new_method
                               end
      end

      def class_to_interface(sig, constructor:)
        type_name = TypeName::Class.new(name: sig.name, constructor: constructor)

        supers = []
        methods = {
          new: Method.new(
            type_name: TypeName::Class.new(name: "Builtin", constructor: true),
            name: :new,
            types: [
              MethodType.new(type_params: [],
                             params: Params.empty,
                             block: nil,
                             return_type: AST::Types::Instance.new,
                             location: nil
              )
            ],
            super_method: nil,
            attributes: []
          )
        }

        klass = build(TypeName::Instance.new(name: ModuleName.parse("::Class")))
        instantiated = klass.instantiate(
          type: AST::Types::Self.new,
          args: [AST::Types::Instance.new],
          instance_type: AST::Types::Instance.new,
          module_type: AST::Types::Class.new
        )
        methods.merge!(instantiated.methods)

        unless sig.name == ModuleName.parse("::BasicObject")
          super_class_name = sig.super_class&.name&.absolute! || ModuleName.parse("::Object")
          merge_mixin(TypeName::Class.new(name: super_class_name, constructor: constructor),
                      [],
                      methods: methods,
                      ivars: {},
                      supers: supers,
                      current: sig.name)
        end

        sig.members.each do |member|
          case member
          when AST::Signature::Members::Include
            merge_mixin(TypeName::Module.new(name: member.name),
                        [],
                        methods: methods,
                        supers: supers,
                        ivars: {},
                        current: sig.name)
          when AST::Signature::Members::Extend
            merge_mixin(TypeName::Instance.new(name: member.name),
                        member.args.map {|type| absolute_type(type, current: sig.name) },
                        methods: methods,
                        ivars: {},
                        supers: supers,
                        current: sig.name)
          end
        end

        sig.members.each do |member|
          case member
          when AST::Signature::Members::Method
            case
            when member.module_method?
              add_method(type_name, member, methods: methods)
            when member.instance_method? && member.name == :initialize
              if constructor
                methods[:new] = Method.new(
                  type_name: type_name,
                  name: :new,
                  types: member.types.map do |method_type_sig|
                    method_type = method_type_to_method_type(method_type_sig, current: sig.name).with(return_type: AST::Types::Instance.new)
                    args = (sig.params&.variables || []) + method_type.type_params

                    method_type.with(
                      type_params: args,
                      return_type: AST::Types::Instance.new
                    )
                  end,
                  super_method: nil,
                  attributes: []
                )
              end
            end
          end
        end

        unless constructor
          methods.delete(:new)
        end

        Abstract.new(
          name: type_name,
          params: [],
          methods: methods,
          supers: supers,
          ivar_chains: {}
        )
      end

      def module_to_interface(sig)
        type_name = TypeName::Module.new(name: sig.name)

        supers = [sig.self_type].compact.map {|type| absolute_type(type, current: nil) }
        methods = {}

        module_instance = build(TypeName::Instance.new(name: ModuleName.parse("::Module")))
        instantiated = module_instance.instantiate(
          type: AST::Types::Self.new,
          args: [],
          instance_type: AST::Types::Instance.new,
          module_type: AST::Types::Class.new
        )
        methods.merge!(instantiated.methods)

        sig.members.each do |member|
          case member
          when AST::Signature::Members::Include
            merge_mixin(TypeName::Module.new(name: member.name),
                        member.args.map {|type| absolute_type(type, current: sig.name) },
                        methods: methods,
                        ivars: {},
                        supers: supers,
                        current: sig.name)
          when AST::Signature::Members::Extend
            merge_mixin(TypeName::Instance.new(name: member.name),
                        member.args.map {|type| absolute_type(type, current: sig.name) },
                        methods: methods,
                        ivars: {},
                        supers: supers,
                        current: sig.name)
          end
        end

        sig.members.each do |member|
          case member
          when AST::Signature::Members::Method
            if member.module_method?
              add_method(type_name, member, methods: methods)
            end
          end
        end

        Abstract.new(
          name: type_name,
          params: [],
          methods: methods,
          supers: supers,
          ivar_chains: {}
        )
      end

      def instance_to_interface(sig, with_initialize:)
        type_name = TypeName::Instance.new(name: sig.name)

        params = sig.params&.variables || []
        supers = []
        methods = {}
        ivar_chains = {}

        if sig.is_a?(AST::Signature::Class)
          unless sig.name == ModuleName.parse("::BasicObject")
            super_class_name = sig.super_class&.name || ModuleName.parse("::Object")
            super_class_interface = build(TypeName::Instance.new(name: super_class_name), current: nil)

            supers.push(*super_class_interface.supers)
            instantiated = super_class_interface.instantiate(
              type: AST::Types::Self.new,
              args: (sig.super_class&.args || []).map {|type| absolute_type(type, current: nil) },
              instance_type: AST::Types::Instance.new,
              module_type: AST::Types::Class.new
            )

            methods.merge!(instantiated.methods)
            merge_ivars(ivar_chains, instantiated.ivars)
          end
        end

        if sig.is_a?(AST::Signature::Module)
          if sig.self_type
            supers << sig.self_type
          end
        end

        sig.members.each do |member|
          case member
          when AST::Signature::Members::Include
            merge_mixin(TypeName::Instance.new(name: member.name),
                        member.args.map {|type| absolute_type(type, current: sig.name) },
                        methods: methods,
                        ivars: ivar_chains,
                        supers: supers,
                        current: sig.name)
          end
        end

        sig.members.each do |member|
          case member
          when AST::Signature::Members::Method
            if member.instance_method?
              if with_initialize || member.name != :initialize
                add_method(type_name, member, methods: methods)
              end
            end
          when AST::Signature::Members::Ivar
            merge_ivars(ivar_chains,
                        { member.name => absolute_type(member.type, current: sig.name) })
          when AST::Signature::Members::Attr
            if member.ivar != false
              ivar_name = member.ivar || "@#{member.name}".to_sym
              merge_ivars(ivar_chains,
                          { ivar_name => absolute_type(member.type, current: sig.name) })
            end

            reader_method = AST::Signature::Members::Method.new(
              location: member.location,
              name: member.name,
              kind: :instance,
              types: [
                AST::MethodType.new(location: member.type.location,
                                    type_params: nil,
                                    params: nil,
                                    block: nil,
                                    return_type: member.type)
              ],
              attributes: []
            )
            add_method(type_name, reader_method, methods: methods)

            if member.accessor?
              writer_method = AST::Signature::Members::Method.new(
                location: member.location,
                name: "#{member.name}=".to_sym,
                kind: :instance,
                types: [
                  AST::MethodType.new(location: member.type.location,
                                      type_params: nil,
                                      params: AST::MethodType::Params::Required.new(location: member.type.location,
                                                                                    type: member.type),
                                      block: nil,
                                      return_type: member.type)
                ],
                attributes: []
              )
              add_method(type_name, writer_method, methods: methods)
            end
          end
        end

        signatures.find_extensions(sig.name).each do |ext|
          ext.members.each do |member|
            case member
            when AST::Signature::Members::Method
              if member.instance_method?
                add_method(type_name, member, methods: methods)
              end
            end
          end
        end

        Abstract.new(
          name: type_name,
          params: params,
          methods: methods,
          supers: supers,
          ivar_chains: ivar_chains
        )
      end

      def merge_ivars(dest, new_vars)
        new_vars.each do |name, new_type|
          dest[name] = IvarChain.new(type: new_type, parent: dest[name])
        end
      end

      def interface_to_interface(_, sig)
        type_name = TypeName::Interface.new(name: sig.name)

        variables = sig.params&.variables || []
        methods = sig.methods.each.with_object({}) do |method, methods|
          methods[method.name] = Method.new(
            type_name: type_name,
            name: method.name,
            types: method.types.map do |method_type|
              method_type_to_method_type(method_type, current: nil)
            end,
            super_method: nil,
            attributes: []
          )
        end

        Abstract.new(
          name: type_name,
          params: variables,
          methods: methods,
          supers: [],
          ivar_chains: {}
        )
      end

      def method_type_to_method_type(method_type, current:)
        type_params = method_type.type_params&.variables || []
        params = params_to_params(method_type.params, current: current)
        block = method_type.block && Block.new(
          params: params_to_params(method_type.block.params, current: current),
          return_type: absolute_type(method_type.block.return_type, current: current)
        )

        MethodType.new(
          type_params: type_params,
          return_type: absolute_type(method_type.return_type, current: current),
          block: block,
          params: params,
          location: method_type.location
        )
      end

      def params_to_params(params, current:)
        required = []
        optional = []
        rest = nil
        required_keywords = {}
        optional_keywords = {}
        rest_keywords = nil

        while params
          case params
          when AST::MethodType::Params::Required
            required << absolute_type(params.type, current: current)
          when AST::MethodType::Params::Optional
            optional << absolute_type(params.type, current: current)
          when AST::MethodType::Params::Rest
            rest = absolute_type(params.type, current: current)
          when AST::MethodType::Params::RequiredKeyword
            required_keywords[params.name] = absolute_type(params.type, current: current)
          when AST::MethodType::Params::OptionalKeyword
            optional_keywords[params.name] = absolute_type(params.type, current: current)
          when AST::MethodType::Params::RestKeyword
            rest_keywords = absolute_type(params.type, current: current)
            break
          end
          params = params.next_params
        end

        Params.new(
          required: required,
          optional: optional,
          rest: rest,
          required_keywords: required_keywords,
          optional_keywords: optional_keywords,
          rest_keywords: rest_keywords
        )
      end
    end
  end
end
