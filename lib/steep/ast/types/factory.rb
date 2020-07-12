module Steep
  module AST
    module Types
      class Factory
        attr_reader :definition_builder

        def initialize(builder:)
          @definition_builder = builder
        end

        def type_name_resolver
          @type_name_resolver ||= RBS::TypeNameResolver.from_env(definition_builder.env)
        end

        def type(type)
          case type
          when RBS::Types::Bases::Any
            Any.new(location: nil)
          when RBS::Types::Bases::Class
            Class.new(location: nil)
          when RBS::Types::Bases::Instance
            Instance.new(location: nil)
          when RBS::Types::Bases::Self
            Self.new(location: nil)
          when RBS::Types::Bases::Top
            Top.new(location: nil)
          when RBS::Types::Bases::Bottom
            Bot.new(location: nil)
          when RBS::Types::Bases::Bool
            Boolean.new(location: nil)
          when RBS::Types::Bases::Void
            Void.new(location: nil)
          when RBS::Types::Bases::Nil
            Nil.new(location: nil)
          when RBS::Types::Variable
            Var.new(name: type.name, location: nil)
          when RBS::Types::ClassSingleton
            type_name = type_name(type.name)
            Name::Class.new(name: type_name, location: nil, constructor: nil)
          when RBS::Types::ClassInstance
            type_name = type_name(type.name)
            args = type.args.map {|arg| type(arg) }
            Name::Instance.new(name: type_name, args: args, location: nil)
          when RBS::Types::Interface
            type_name = type_name(type.name)
            args = type.args.map {|arg| type(arg) }
            Name::Interface.new(name: type_name, args: args, location: nil)
          when RBS::Types::Alias
            type_name = type_name(type.name)
            Name::Alias.new(name: type_name, args: [], location: nil)
          when RBS::Types::Union
            Union.build(types: type.types.map {|ty| type(ty) }, location: nil)
          when RBS::Types::Intersection
            Intersection.build(types: type.types.map {|ty| type(ty) }, location: nil)
          when RBS::Types::Optional
            Union.build(types: [type(type.type), Nil.new(location: nil)], location: nil)
          when RBS::Types::Literal
            Literal.new(value: type.literal, location: nil)
          when RBS::Types::Tuple
            Tuple.new(types: type.types.map {|ty| type(ty) }, location: nil)
          when RBS::Types::Record
            elements = type.fields.each.with_object({}) do |(key, value), hash|
              hash[key] = type(value)
            end
            Record.new(elements: elements, location: nil)
          when RBS::Types::Proc
            params = params(type.type)
            return_type = type(type.type.return_type)
            Proc.new(params: params, return_type: return_type, location: nil)
          else
            raise "Unexpected type given: #{type}"
          end
        end

        def type_1(type)
          case type
          when Any
            RBS::Types::Bases::Any.new(location: nil)
          when Class
            RBS::Types::Bases::Class.new(location: nil)
          when Instance
            RBS::Types::Bases::Instance.new(location: nil)
          when Self
            RBS::Types::Bases::Self.new(location: nil)
          when Top
            RBS::Types::Bases::Top.new(location: nil)
          when Bot
            RBS::Types::Bases::Bottom.new(location: nil)
          when Boolean
            RBS::Types::Bases::Bool.new(location: nil)
          when Void
            RBS::Types::Bases::Void.new(location: nil)
          when Nil
            RBS::Types::Bases::Nil.new(location: nil)
          when Var
            RBS::Types::Variable.new(name: type.name, location: nil)
          when Name::Class, Name::Module
            RBS::Types::ClassSingleton.new(name: type_name_1(type.name), location: nil)
          when Name::Instance
            RBS::Types::ClassInstance.new(
              name: type_name_1(type.name),
              args: type.args.map {|arg| type_1(arg) },
              location: nil
            )
          when Name::Interface
            RBS::Types::Interface.new(
              name: type_name_1(type.name),
              args: type.args.map {|arg| type_1(arg) },
              location: nil
            )
          when Name::Alias
            type.args.empty? or raise "alias type with args is not supported"
            RBS::Types::Alias.new(name: type_name_1(type.name), location: nil)
          when Union
            RBS::Types::Union.new(
              types: type.types.map {|ty| type_1(ty) },
              location: nil
            )
          when Intersection
            RBS::Types::Intersection.new(
              types: type.types.map {|ty| type_1(ty) },
              location: nil
            )
          when Literal
            RBS::Types::Literal.new(literal: type.value, location: nil)
          when Tuple
            RBS::Types::Tuple.new(
              types: type.types.map {|ty| type_1(ty) },
              location: nil
            )
          when Record
            fields = type.elements.each.with_object({}) do |(key, value), hash|
              hash[key] = type_1(value)
            end
            RBS::Types::Record.new(fields: fields, location: nil)
          when Proc
            RBS::Types::Proc.new(
              type: function_1(type.params, type.return_type),
              location: nil
            )
          else
            raise "Unexpected type given: #{type} (#{type.class})"
          end
        end

        def type_name(name)
          case
          when name.class?
            Names::Module.new(name: name.name, namespace: namespace(name.namespace), location: nil)
          when name.interface?
            Names::Interface.new(name: name.name, namespace: namespace(name.namespace), location: nil)
          when name.alias?
            Names::Alias.new(name: name.name, namespace: namespace(name.namespace), location: nil)
          end
        end

        def type_name_1(name)
          RBS::TypeName.new(name: name.name, namespace: namespace_1(name.namespace))
        end

        def namespace(namespace)
          Namespace.parse(namespace.to_s)
        end

        def namespace_1(namespace)
          RBS::Namespace.parse(namespace.to_s)
        end

        def function_1(params, return_type)
          RBS::Types::Function.new(
            required_positionals: params.required.map {|type| RBS::Types::Function::Param.new(name: nil, type: type_1(type)) },
            optional_positionals: params.optional.map {|type| RBS::Types::Function::Param.new(name: nil, type: type_1(type)) },
            rest_positionals: params.rest&.yield_self {|type| RBS::Types::Function::Param.new(name: nil, type: type_1(type)) },
            trailing_positionals: [],
            required_keywords: params.required_keywords.transform_values {|type| RBS::Types::Function::Param.new(name: nil, type: type_1(type)) },
            optional_keywords: params.optional_keywords.transform_values {|type| RBS::Types::Function::Param.new(name: nil, type: type_1(type)) },
            rest_keywords: params.rest_keywords&.yield_self {|type| RBS::Types::Function::Param.new(name: nil, type: type_1(type)) },
            return_type: type_1(return_type)
          )
        end

        def params(type)
          Interface::Params.new(
            required: type.required_positionals.map {|param| type(param.type) },
            optional: type.optional_positionals.map {|param| type(param.type) },
            rest: type.rest_positionals&.yield_self {|param| type(param.type) },
            required_keywords: type.required_keywords.transform_values {|param| type(param.type) },
            optional_keywords: type.optional_keywords.transform_values {|param| type(param.type) },
            rest_keywords: type.rest_keywords&.yield_self {|param| type(param.type) }
          )
        end

        def method_type(method_type, self_type:)
          fvs = self_type.free_variables()

          type_params = []
          alpha_vars = []
          alpha_types = []

          method_type.type_params.map do |name|
            if fvs.include?(name)
              type = Types::Var.fresh(name)
              alpha_vars << name
              alpha_types << type
              type_params << type.name
            else
              type_params << name
            end
          end
          subst = Interface::Substitution.build(alpha_vars, alpha_types)

          type = Interface::MethodType.new(
            type_params: type_params,
            return_type: type(method_type.type.return_type).subst(subst),
            params: params(method_type.type).subst(subst),
            location: nil,
            block: method_type.block&.yield_self do |block|
              Interface::Block.new(
                optional: !block.required,
                type: Proc.new(params: params(block.type).subst(subst),
                               return_type: type(block.type.return_type).subst(subst), location: nil)
              )
            end
          )

          if block_given?
            yield type
          else
            type
          end
        end

        def method_type_1(method_type, self_type:)
          fvs = self_type.free_variables()

          type_params = []
          alpha_vars = []
          alpha_types = []

          method_type.type_params.map do |name|
            if fvs.include?(name)
              type = RBS::Types::Variable.new(name: name, location: nil),
              alpha_vars << name
              alpha_types << type
              type_params << type.name
            else
              type_params << name
            end
          end
          subst = Interface::Substitution.build(alpha_vars, alpha_types)

          type = RBS::MethodType.new(
            type_params: type_params,
            type: function_1(method_type.params.subst(subst), method_type.return_type.subst(subst)),
            block: method_type.block&.yield_self do |block|
              block_type = block.type.subst(subst)

              RBS::MethodType::Block.new(
                type: function_1(block_type.params, block_type.return_type),
                required: !block.optional
              )
            end,
            location: nil
          )

          if block_given?
            yield type
          else
            type
          end
        end

        class InterfaceCalculationError < StandardError
          attr_reader :type

          def initialize(type:, message:)
            @type = type
            super message
          end
        end

        def unfold(type_name)
          type_name_1(type_name).yield_self do |type_name|
            type(definition_builder.expand_alias(type_name))
          end
        end

        def expand_alias(type)
          unfolded = case type
                     when AST::Types::Name::Alias
                       unfolded = unfold(type.name)
                     else
                       type
                     end

          if block_given?
            yield unfolded
          else
            unfolded
          end
        end

        def interface(type, private:, self_type: type)
          type = expand_alias(type)

          case type
          when Self
            if self_type != type
              interface self_type, private: private, self_type: Self.new
            else
              raise "Unexpected `self` type interface"
            end
          when Name::Instance
            Interface::Interface.new(type: self_type, private: private).tap do |interface|
              definition = definition_builder.build_instance(type_name_1(type.name))

              instance_type = Name::Instance.new(name: type.name,
                                                 args: type.args.map { Any.new(location: nil) },
                                                 location: nil)
              module_type = type.to_module()

              subst = Interface::Substitution.build(
                definition.type_params,
                type.args,
                instance_type: instance_type,
                module_type: module_type,
                self_type: self_type
              )

              definition.methods.each do |name, method|
                next if method.private? && !private

                interface.methods[name] = Interface::Interface::Combination.overload(
                  method.method_types.map do |type|
                    method_type(type, self_type: self_type) {|ty| ty.subst(subst) }
                  end,
                  incompatible: name == :initialize || name == :new
                )
              end
            end

          when Name::Interface
            Interface::Interface.new(type: self_type, private: private).tap do |interface|
              type_name = type_name_1(type.name)
              definition = definition_builder.build_interface(type_name)

              subst = Interface::Substitution.build(
                definition.type_params,
                type.args,
                self_type: self_type
              )

              definition.methods.each do |name, method|
                interface.methods[name] = Interface::Interface::Combination.overload(
                  method.method_types.map do |type|
                    method_type(type, self_type: self_type) {|type| type.subst(subst) }
                  end,
                  incompatible: method.attributes.include?(:incompatible)
                )
              end
            end

          when Name::Class, Name::Module
            Interface::Interface.new(type: self_type, private: private).tap do |interface|
              definition = definition_builder.build_singleton(type_name_1(type.name))

              instance_type = Name::Instance.new(name: type.name,
                                                 args: definition.type_params.map {Any.new(location: nil)},
                                                 location: nil)
              subst = Interface::Substitution.build(
                [],
                instance_type: instance_type,
                module_type: type,
                self_type: self_type
              )

              definition.methods.each do |name, method|
                next if !private && method.private?

                interface.methods[name] = Interface::Interface::Combination.overload(
                  method.method_types.map do |type|
                    method_type(type, self_type: self_type) {|type| type.subst(subst) }
                  end,
                  incompatible: method.attributes.include?(:incompatible)
                )
              end
            end

          when Literal
            interface type.back_type, private: private, self_type: self_type

          when Nil
            interface Builtin::NilClass.instance_type, private: private, self_type: self_type

          when Boolean
            interface(AST::Types::Union.build(types: [Builtin::TrueClass.instance_type, Builtin::FalseClass.instance_type]),
                      private: private,
                      self_type: self_type)

          when Union
            yield_self do
              interfaces = type.types.map {|ty| interface(ty, private: private, self_type: self_type) }
              interfaces.inject do |interface1, interface2|
                Interface::Interface.new(type: self_type, private: private).tap do |interface|
                  common_methods = Set.new(interface1.methods.keys) & Set.new(interface2.methods.keys)
                  common_methods.each do |name|
                    interface.methods[name] = Interface::Interface::Combination.union([interface1.methods[name], interface2.methods[name]])
                  end
                end
              end
            end

          when Intersection
            yield_self do
              interfaces = type.types.map {|ty| interface(ty, private: private, self_type: self_type) }
              interfaces.inject do |interface1, interface2|
                Interface::Interface.new(type: self_type, private: private).tap do |interface|
                  all_methods = Set.new(interface1.methods.keys) + Set.new(interface2.methods.keys)
                  all_methods.each do |name|
                    methods = [interface1.methods[name], interface2.methods[name]].compact
                    interface.methods[name] = Interface::Interface::Combination.intersection(methods)
                  end
                end
              end
            end

          when Tuple
            yield_self do
              element_type = Union.build(types: type.types, location: nil)
              array_type = Builtin::Array.instance_type(element_type)
              interface(array_type, private: private, self_type: self_type).tap do |array_interface|
                array_interface.methods[:[]] = array_interface.methods[:[]].yield_self do |aref|
                  Interface::Interface::Combination.overload(
                    type.types.map.with_index {|elem_type, index|
                      Interface::MethodType.new(
                        type_params: [],
                        params: Interface::Params.new(required: [AST::Types::Literal.new(value: index)],
                                                      optional: [],
                                                      rest: nil,
                                                      required_keywords: {},
                                                      optional_keywords: {},
                                                      rest_keywords: nil),
                        block: nil,
                        return_type: elem_type,
                        location: nil
                      )
                    } + aref.types,
                    incompatible: false
                  )
                end

                array_interface.methods[:[]=] = array_interface.methods[:[]=].yield_self do |update|
                  Interface::Interface::Combination.overload(
                    type.types.map.with_index {|elem_type, index|
                      Interface::MethodType.new(
                        type_params: [],
                        params: Interface::Params.new(required: [AST::Types::Literal.new(value: index), elem_type],
                                                      optional: [],
                                                      rest: nil,
                                                      required_keywords: {},
                                                      optional_keywords: {},
                                                      rest_keywords: nil),
                        block: nil,
                        return_type: elem_type,
                        location: nil
                      )
                    } + update.types,
                    incompatible: false
                  )
                end
              end
            end

          when Record
            yield_self do
              key_type = type.elements.keys.map {|value| Literal.new(value: value, location: nil) }.yield_self do |types|
                Union.build(types: types, location: nil)
              end
              value_type = Union.build(types: type.elements.values, location: nil)
              hash_type = Builtin::Hash.instance_type(key_type, value_type)

              interface(hash_type, private: private, self_type: self_type).tap do |hash_interface|
                hash_interface.methods[:[]] = hash_interface.methods[:[]].yield_self do |ref|
                  Interface::Interface::Combination.overload(
                    type.elements.map {|key_value, value_type|
                      key_type = Literal.new(value: key_value, location: nil)
                      Interface::MethodType.new(
                        type_params: [],
                        params: Interface::Params.new(required: [key_type],
                                                      optional: [],
                                                      rest: nil,
                                                      required_keywords: {},
                                                      optional_keywords: {},
                                                      rest_keywords: nil),
                        block: nil,
                        return_type: value_type,
                        location: nil
                      )
                    } + ref.types,
                    incompatible: false
                  )
                end

                hash_interface.methods[:[]=] = hash_interface.methods[:[]=].yield_self do |update|
                  Interface::Interface::Combination.overload(
                    type.elements.map {|key_value, value_type|
                      key_type = Literal.new(value: key_value, location: nil)
                      Interface::MethodType.new(
                        type_params: [],
                        params: Interface::Params.new(required: [key_type, value_type],
                                                      optional: [],
                                                      rest: nil,
                                                      required_keywords: {},
                                                      optional_keywords: {},
                                                      rest_keywords: nil),
                        block: nil,
                        return_type: value_type,
                        location: nil
                      )
                    } + update.types,
                    incompatible: false
                  )
                end
              end
            end

          when Proc
            interface(Builtin::Proc.instance_type, private: private, self_type: self_type).tap do |interface|
              method_type = Interface::MethodType.new(
                type_params: [],
                params: type.params,
                return_type: type.return_type,
                block: nil,
                location: nil
              )

              interface.methods[:[]] = Interface::Interface::Combination.overload([method_type], incompatible: false)
              interface.methods[:call] = Interface::Interface::Combination.overload([method_type], incompatible: false)
            end

          else
            raise "Unexpected type for interface: #{type}"
          end
        end

        def module_name?(type_name)
          name = type_name_1(type_name)
          entry = env.class_decls[name] and entry.is_a?(RBS::Environment::ModuleEntry)
        end

        def class_name?(type_name)
          name = type_name_1(type_name)
          entry = env.class_decls[name] and entry.is_a?(RBS::Environment::ClassEntry)
        end

        def env
          @env ||= definition_builder.env
        end

        def absolute_type(type, namespace:)
          absolute_type = type_1(type).map_type_name do |name|
            absolute_type_name(name, namespace: namespace) || name.absolute!
          end
          type(absolute_type)
        end

        def absolute_type_name(type_name, namespace:)
          type_name_resolver.resolve(type_name, context: namespace_1(namespace).ascend)
        end
      end
    end
  end
end
