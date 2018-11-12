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
      attr_reader :class_cache
      attr_reader :module_cache
      attr_reader :instance_cache
      attr_reader :interface_cache

      def initialize(signatures:)
        @signatures = signatures
        @class_cache = {}
        @module_cache = {}
        @instance_cache = {}
        @interface_cache = {}
      end

      def absolute_type(type, current:)
        case type
        when AST::Types::Name::Instance
          signature = signatures.find_class_or_module(type.name, current_module: current)
          AST::Types::Name::Instance.new(
            name: signature.name,
            args: type.args.map {|arg| absolute_type(arg, current: current) },
            location: type.location
          )
        when AST::Types::Name::Class
          signature = signatures.find_class(type.name, current_module: current)
          AST::Types::Name::Class.new(
            name: signature.name,
            constructor: type.constructor,
            location: type.location
          )
        when AST::Types::Name::Module
          signature = signatures.find_class_or_module(type.name, current_module: current)
          AST::Types::Name::Module.new(
            name: signature.name,
            location: type.location
          )
        when AST::Types::Name::Interface
          signature = signatures.find_interface(type.name, namespace: current)
          AST::Types::Name::Interface.new(
            name: signature.name,
            args: type.args.map {|arg| absolute_type(arg, current: current) },
            location: type.location
          )
        when AST::Types::Name::Alias
          signature = signatures.find_alias(type.name, namespace: current)
          AST::Types::Name::Alias.new(
            name: signature.name,
            args: type.args.map {|arg| absolute_type(arg, current: current) },
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
        when AST::Types::Proc
          AST::Types::Proc.new(
            params: type.params.map_type {|ty| absolute_type(ty, current: current) },
            return_type: absolute_type(type.return_type, current: current),
            location: type.location
          )
        when AST::Types::Record
          AST::Types::Record.new(
            elements: type.elements.transform_values {|ty| absolute_type(ty, current: current) },
            location: type.location
          )
        else
          type
        end
      end

      def cache_interface(cache, key:, &block)
        cached = cache[key]

        case cached
        when nil
          cache[key] = key
          cache[key] = yield
        when key
          raise RecursiveDefinitionError, key
        else
          cached
        end
      rescue RecursiveDefinitionError => exn
        cache.delete key
        raise exn
      end

      def assert_absolute_name!(name)
        raise "Name should be absolute: #{name}" unless name.absolute?
      end

      def build_class(module_name, constructor:)
        assert_absolute_name! module_name
        signature = signatures.find_class(module_name, current_module: AST::Namespace.root)
        cache_interface(class_cache, key: [signature.name, !!constructor]) do
          class_to_interface(signature, constructor: constructor)
        end
      end

      def build_module(module_name)
        assert_absolute_name! module_name
        signature = signatures.find_module(module_name, current_module: AST::Namespace.root)
        cache_interface(module_cache, key: signature.name) do
          module_to_interface(signature)
        end
      end

      def build_instance(module_name)
        assert_absolute_name! module_name
        signature = signatures.find_class_or_module(module_name, current_module: AST::Namespace.root)
        cache_interface(instance_cache, key: signature.name) do
          instance_to_interface(signature)
        end
      end

      def build_interface(interface_name)
        signature = signatures.find_interface(interface_name)
        cache_interface(interface_cache, key: [signature.name]) do
          interface_to_interface(nil, signature)
        end
      end

      def merge_mixin(interface, args, methods:, ivars:, supers:, current:)
        supers.push(*interface.supers)

        instantiated = interface.instantiate(
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

      def add_method(type_name, method, methods:, extra_attributes: [], current:)
        super_method = methods[method.name]
        new_method = Method.new(
          type_name: type_name,
          name: method.name,
          types: method.types.flat_map do |method_type|
            case method_type
            when AST::MethodType
              [method_type_to_method_type(method_type, current: current)]
            when AST::MethodType::Super
              if super_method
                super_method.types
              else
                Steep.logger.error "`super` specified in method type, but cannot find super method of `#{method.name}` in `#{type_name}` (#{method.location.name || "-"}:#{method.location})"
                []
              end
            end
          end,
          super_method: super_method,
          attributes: method.attributes + extra_attributes
        )

        methods[method.name] = if super_method&.include_in_chain?(new_method)
                                 super_method
                               else
                                 new_method
                               end
      end

      def class_to_interface(sig, constructor:)
        module_name = sig.name
        namespace = module_name.namespace.append(module_name.name)

        supers = []
        methods = {
          new: Method.new(
            type_name: Names::Module.parse(name: "__Builtin__"),
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
            attributes: [:incompatible]
          )
        }

        klass = build_instance(AST::Builtin::Class.module_name)
        instantiated = klass.instantiate(
          type: AST::Types::Self.new,
          args: [],
          instance_type: AST::Types::Instance.new,
          module_type: AST::Types::Class.new
        )
        methods.merge!(instantiated.methods)

        unless module_name == AST::Builtin::BasicObject.module_name
          super_class_name = sig.super_class&.name&.yield_self {|name| signatures.find_class(name, current_module: namespace).name } || AST::Builtin::Object.module_name
          class_interface = build_class(super_class_name, constructor: constructor)
          merge_mixin(class_interface, [], methods: methods, ivars: {}, supers: supers, current: namespace)
        end

        sig.members.each do |member|
          case member
          when AST::Signature::Members::Include
            member_name = signatures.find_module(member.name, current_module: namespace).name
            build_module(member_name).yield_self do |module_interface|
              merge_mixin(module_interface,
                          [],
                          methods: methods,
                          supers: supers,
                          ivars: {},
                          current: namespace)
            end
          when AST::Signature::Members::Extend
            member_name = signatures.find_module(member.name, current_module: namespace).name
            build_instance(member_name).yield_self do |module_interface|
              merge_mixin(module_interface,
                          member.args.map {|type| absolute_type(type, current: namespace) },
                          methods: methods,
                          ivars: {},
                          supers: supers,
                          current: namespace)
            end
          end
        end

        sig.members.each do |member|
          case member
          when AST::Signature::Members::Method
            case
            when member.module_method?
              add_method(module_name, member, methods: methods, current: namespace)
            when member.instance_method? && member.name == :initialize
              if constructor
                methods[:new] = Method.new(
                  type_name: module_name,
                  name: :new,
                  types: member.types.map do |method_type_sig|
                    method_type = method_type_to_method_type(method_type_sig, current: namespace).with(return_type: AST::Types::Instance.new)
                    args = (sig.params&.variables || []) + method_type.type_params

                    method_type.with(
                      type_params: args,
                      return_type: AST::Types::Instance.new
                    )
                  end,
                  super_method: nil,
                  attributes: [:incompatible]
                )
              end
            end
          end
        end

        signatures.find_extensions(sig.name).each do |ext|
          ext.members.each do |member|
            case member
            when AST::Signature::Members::Method
              if member.module_method?
                add_method(module_name, member, methods: methods, current: namespace)
              end
            end
          end
        end

        if methods[:new]&.type_name == AST::Builtin::Class.module_name
          new_types = [MethodType.new(type_params: [],
                                      params: Params.empty,
                                      block: nil,
                                      return_type: AST::Types::Instance.new,
                                      location: nil)]
          methods[:new] = methods[:new].with_types(new_types)
        end

        unless constructor
          methods.delete(:new)
        end

        Abstract.new(
          name: module_name,
          params: [],
          methods: methods,
          supers: supers,
          ivar_chains: {}
        )
      end

      def module_to_interface(sig)
        module_name = sig.name
        namespace = module_name.namespace.append(module_name.name)

        supers = [sig.self_type].compact.map {|type| absolute_type(type, current: namespace) }
        methods = {}
        ivar_chains = {}

        module_instance = build_instance(AST::Builtin::Module.module_name)
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
            member_name = signatures.find_module(member.name, current_module: namespace).name
            build_module(member_name).yield_self do |module_interface|
              merge_mixin(module_interface,
                          member.args.map {|type| absolute_type(type, current: namespace) },
                          methods: methods,
                          ivars: ivar_chains,
                          supers: supers,
                          current: namespace)
            end
          when AST::Signature::Members::Extend
            member_name = signatures.find_module(member.name, current_module: namespace).name
            build_instance(member_name).yield_self do |module_interface|
              merge_mixin(module_interface,
                          member.args.map {|type| absolute_type(type, current: namespace) },
                          methods: methods,
                          ivars: ivar_chains,
                          supers: supers,
                          current: namespace)

            end
          end
        end

        sig.members.each do |member|
          case member
          when AST::Signature::Members::Method
            if member.module_method?
              add_method(module_name, member, methods: methods, current: namespace)
            end
          when AST::Signature::Members::Ivar
            merge_ivars(ivar_chains,
                        { member.name => absolute_type(member.type, current: namespace) })
          when AST::Signature::Members::Attr
            merge_attribute(sig, ivar_chains, methods, module_name, member)
          end
        end

        signatures.find_extensions(module_name).each do |ext|
          ext.members.each do |member|
            case member
            when AST::Signature::Members::Method
              if member.module_method?
                add_method(module_name, member, methods: methods, current: namespace)
              end
            end
          end
        end

        Abstract.new(
          name: module_name,
          params: [],
          methods: methods,
          supers: supers,
          ivar_chains: ivar_chains
        )
      end

      def instance_to_interface(sig)
        module_name = sig.name
        namespace = module_name.namespace.append(module_name.name)

        params = sig.params&.variables || []
        supers = []
        methods = {}
        ivar_chains = {}

        if sig.is_a?(AST::Signature::Class)
          unless sig.name == AST::Builtin::BasicObject.module_name
            super_class_name = sig.super_class&.name || AST::Builtin::Object.module_name
            if super_class_name.relative?
              super_class_name = signatures.find_class(super_class_name, current_module: namespace).name
            end
            super_class_interface = build_instance(super_class_name)

            supers.push(*super_class_interface.supers)
            instantiated = super_class_interface.instantiate(
              type: AST::Types::Self.new,
              args: (sig.super_class&.args || []).map {|type| absolute_type(type, current: namespace) },
              instance_type: AST::Types::Instance.new,
              module_type: AST::Types::Class.new
            )

            methods.merge!(instantiated.methods)
            merge_ivars(ivar_chains, instantiated.ivars)
          end
        end

        if sig.is_a?(AST::Signature::Module)
          if sig.self_type
            supers << absolute_type(sig.self_type, current: namespace)
          end
        end

        sig.members.each do |member|
          case member
          when AST::Signature::Members::Include
            member_name = signatures.find_module(member.name, current_module: namespace).name
            build_instance(member_name).yield_self do |module_interface|
              merge_mixin(module_interface,
                          member.args.map {|type| absolute_type(type, current: namespace) },
                          methods: methods,
                          ivars: ivar_chains,
                          supers: supers,
                          current: namespace)
            end
          end
        end

        sig.members.each do |member|
          case member
          when AST::Signature::Members::Method
            if member.instance_method?
              extra_attrs = member.name == :initialize ? [:incompatible, :private] : []
              add_method(module_name, member, methods: methods, extra_attributes: extra_attrs, current: namespace)
            end
          when AST::Signature::Members::Ivar
            merge_ivars(ivar_chains,
                        { member.name => absolute_type(member.type, current: namespace) })
          when AST::Signature::Members::Attr
            merge_attribute(sig, ivar_chains, methods, module_name, member, current: namespace)
          end
        end

        sig.members.each do |member|
          case member
          when AST::Signature::Members::MethodAlias
            method = methods[member.original_name]
            if method
              methods[member.new_name] =  Method.new(
                type_name: module_name,
                name: member.new_name,
                types: method.types,
                super_method: nil,
                attributes: method.attributes
              )
            else
              Steep.logger.error "Cannot alias find original method `#{member.original_name}` for `#{member.new_name}` in #{module_name} (#{member.location.name || '-'}:#{member.location})"
            end
          end
        end

        signatures.find_extensions(sig.name).each do |ext|
          ext.members.each do |member|
            case member
            when AST::Signature::Members::Method
              if member.instance_method?
                add_method(module_name, member, methods: methods, current: namespace)
              end
            end
          end
        end

        Abstract.new(
          name: module_name,
          params: params,
          methods: methods,
          supers: supers,
          ivar_chains: ivar_chains
        )
      end

      def merge_attribute(sig, ivar_chains, methods, type_name, member, current:)
        if member.ivar != false
          ivar_name = member.ivar || "@#{member.name}".to_sym
          merge_ivars(ivar_chains,
                      { ivar_name => absolute_type(member.type, current: current) })
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
        add_method(type_name, reader_method, methods: methods, current: current)

        if member.accessor?
          writer_method = AST::Signature::Members::Method.new(
            location: member.location,
            name: "#{member.name}=".to_sym,
            kind: :instance,
            types: [
              AST::MethodType.new(location: member.type.location,
                                  type_params: nil,
                                  params: AST::MethodType::Params::Required.new(
                                    location: member.type.location,
                                    type: member.type
                                  ),
                                  block: nil,
                                  return_type: member.type)
            ],
            attributes: []
          )
          add_method(type_name, writer_method, methods: methods, current: current)
        end
      end

      def merge_ivars(dest, new_vars)
        new_vars.each do |name, new_type|
          dest[name] = IvarChain.new(type: new_type, parent: dest[name])
        end
      end

      def interface_to_interface(_, sig)
        type_name = sig.name

        variables = sig.params&.variables || []
        methods = sig.methods.each.with_object({}) do |method, methods|
          methods[method.name] = Method.new(
            type_name: type_name,
            name: method.name,
            types: method.types.map do |method_type|
              method_type_to_method_type(method_type, current: type_name.namespace)
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
          type: AST::Types::Proc.new(
            params: params_to_params(method_type.block.params, current: current),
            return_type: absolute_type(method_type.block.return_type, current: current),
            location: method_type.block.location,
            ),
          optional: method_type.block.optional
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
