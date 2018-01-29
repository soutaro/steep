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

      def build(type_name)
        cached = cache[type_name]

        case cached
        when nil
          begin
            cache[type_name] = type_name

            interface = case type_name
                        when TypeName::Instance
                          instance_to_interface(signatures.find_class_or_module(type_name.name))
                        when TypeName::Module
                          module_to_interface(signatures.find_module(type_name.name))
                        when TypeName::Class
                          class_to_interface(signatures.find_class_or_module(type_name.name),
                                              constructor: type_name.constructor)
                        when TypeName::Interface
                          interface_to_interface(type_name.name,
                                                 signatures.find_interface(type_name.name))
                        end

            cache[type_name] = interface
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

      def merge_mixin(type_name, args, methods:, supers:)
        mixed = build(type_name)

        supers.push(*mixed.supers)
        instantiated = mixed.instantiate(
          type: nil,
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
      end

      def add_method(type_name, method, methods:)
        super_method = methods[method.name]
        new_method = Method.new(
          type_name: type_name,
          name: method.name,
          types: method.types.map do |method_type|
            method_type_to_method_type(method_type)
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

        params = sig.params&.variables || []
        supers = []
        methods = {}

        klass = build(TypeName::Instance.new(name: :Class))
        instantiated = klass.instantiate(
          type: nil,
          args: [AST::Types::Instance.new],
          instance_type: AST::Types::Instance.new,
          module_type: AST::Types::Class.new
        )
        methods.merge!(instantiated.methods)

        unless sig.name == :BasicObject
          super_class_name = sig.super_class&.name || :Object
          merge_mixin(TypeName::Class.new(name: super_class_name, constructor: constructor),
                      [],
                      methods: methods,
                      supers: supers)
        end

        sig.members.each do |member|
          case member
          when AST::Signature::Members::Include
            merge_mixin(TypeName::Module.new(name: member.name),
                        member.args,
                        methods: methods,
                        supers: supers)
          when AST::Signature::Members::Extend
            merge_mixin(TypeName::Instance.new(name: member.name),
                        member.args,
                        methods: methods,
                        supers: supers)
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
                  types: member.types.map do |method_type|
                    method_type_to_method_type(method_type,
                                               return_type_override: AST::Types::Instance.new)
                  end,
                  super_method: nil,
                  attributes: []
                )
              end
            end
          end
        end

        Abstract.new(
          name: type_name,
          params: params,
          methods: methods,
          supers: supers
        )
      end

      def module_to_interface(sig)
        type_name = TypeName::Module.new(name: sig.name)

        params = sig.params&.variables || []
        supers = []
        methods = {}

        module_instance = build(TypeName::Instance.new(name: :Module))
        instantiated = module_instance.instantiate(
          type: nil,
          args: [],
          instance_type: AST::Types::Instance.new,
          module_type: AST::Types::Class.new
        )
        methods.merge!(instantiated.methods)

        sig.members.each do |member|
          case member
          when AST::Signature::Members::Include
            merge_mixin(TypeName::Module.new(name: member.name),
                        member.args,
                        methods: methods,
                        supers: supers)
          when AST::Signature::Members::Extend
            merge_mixin(TypeName::Instance.new(name: member.name),
                        member.args,
                        methods: methods,
                        supers: supers)
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
          params: params,
          methods: methods,
          supers: supers
        )
      end

      def instance_to_interface(sig)
        type_name = TypeName::Instance.new(name: sig.name)

        params = sig.params&.variables || []
        supers = []
        methods = {}

        if sig.is_a?(AST::Signature::Class)
          unless sig.name == :BasicObject
            super_class_name = sig.super_class&.name || :Object
            super_class_interface = build(TypeName::Instance.new(name: super_class_name))

            supers.push(*super_class_interface.supers)
            instantiated = super_class_interface.instantiate(
              type: nil,
              args: sig.super_class&.args || [],
              instance_type: AST::Types::Instance.new,
              module_type: AST::Types::Class.new
            )

            methods.merge!(instantiated.methods)
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
                        member.args,
                        methods: methods,
                        supers: supers)
          end
        end

        sig.members.each do |member|
          case member
          when AST::Signature::Members::Method
            if member.instance_method?
              add_method(type_name, member, methods: methods)
            end
          end
        end

        Abstract.new(
          name: type_name,
          params: params,
          methods: methods,
          supers: supers
        )
      end

      def interface_to_interface(_, sig)
        type_name = TypeName::Interface.new(name: sig.name)

        variables = sig.params&.variables || []
        methods = sig.methods.each.with_object({}) do |method, methods|
          methods[method.name] = Method.new(
            type_name: type_name,
            name: method.name,
            types: method.types.map do |method_type|
              method_type_to_method_type(method_type)
            end,
            super_method: nil,
            attributes: []
          )
        end

        Abstract.new(
          name: type_name,
          params: variables,
          methods: methods,
          supers: []
        )
      end

      def method_type_to_method_type(method_type, return_type_override: nil)
        type_params = method_type.type_params&.variables || []
        params = params_to_params(method_type.params)
        block = method_type.block && Block.new(
          params: params_to_params(method_type.block.params),
          return_type: method_type.block.return_type
        )

        MethodType.new(
          type_params: type_params,
          return_type: return_type_override || method_type.return_type,
          block: block,
          params: params,
          location: method_type.location
        )
      end

      def params_to_params(params)
        required = []
        optional = []
        rest = nil
        required_keywords = {}
        optional_keywords = {}
        rest_keywords = nil

        while params
          case params
          when AST::MethodType::Params::Required
            required << params.type
          when AST::MethodType::Params::Optional
            optional << params.type
          when AST::MethodType::Params::Rest
            rest = params.type
          when AST::MethodType::Params::RequiredKeyword
            required_keywords[params.name] = params.type
          when AST::MethodType::Params::OptionalKeyword
            optional_keywords[params.name] = params.type
          when AST::MethodType::Params::RestKeyword
            rest_keywords = params.type
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
