module Steep
  module AST
    module Types
      class Factory
        attr_reader :definition_builder

        def initialize(builder:)
          @definition_builder = builder
        end

        def type(type)
          case type
          when Ruby::Signature::Types::Bases::Any
            Any.new(location: nil)
          when Ruby::Signature::Types::Bases::Class
            Class.new(location: nil)
          when Ruby::Signature::Types::Bases::Instance
            Instance.new(location: nil)
          when Ruby::Signature::Types::Bases::Self
            Self.new(location: nil)
          when Ruby::Signature::Types::Bases::Top
            Top.new(location: nil)
          when Ruby::Signature::Types::Bases::Bottom
            Bot.new(location: nil)
          when Ruby::Signature::Types::Bases::Bool
            Boolean.new(location: nil)
          when Ruby::Signature::Types::Bases::Void
            Void.new(location: nil)
          when Ruby::Signature::Types::Bases::Nil
            Nil.new(location: nil)
          when Ruby::Signature::Types::Variable
            Var.new(name: type.name, location: nil)
          when Ruby::Signature::Types::ClassSingleton
            type_name = type_name(type.name)
            Name::Class.new(name: type_name, location: nil, constructor: nil)
          when Ruby::Signature::Types::ClassInstance
            type_name = type_name(type.name)
            args = type.args.map {|arg| type(arg) }
            Name::Instance.new(name: type_name, args: args, location: nil)
          when Ruby::Signature::Types::Interface
            type_name = type_name(type.name)
            args = type.args.map {|arg| type(arg) }
            Name::Interface.new(name: type_name, args: args, location: nil)
          when Ruby::Signature::Types::Alias
            type_name = type_name(type.name)
            Name::Alias.new(name: type_name, args: [], location: nil)
          when Ruby::Signature::Types::Union
            Union.build(types: type.types.map {|ty| type(ty) }, location: nil)
          when Ruby::Signature::Types::Intersection
            Intersection.build(types: type.types.map {|ty| type(ty) }, location: nil)
          when Ruby::Signature::Types::Optional
            Union.build(types: [type(type.type), Nil.new(location: nil)], location: nil)
          when Ruby::Signature::Types::Literal
            Literal.new(value: type.literal, location: nil)
          when Ruby::Signature::Types::Tuple
            Tuple.new(types: type.types.map {|ty| type(ty) }, location: nil)
          when Ruby::Signature::Types::Record
            elements = type.fields.each.with_object({}) do |(key, value), hash|
              hash[key] = type(value)
            end
            Record.new(elements: elements, location: nil)
          when Ruby::Signature::Types::Proc
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
            Ruby::Signature::Types::Bases::Any.new(location: nil)
          when Class
            Ruby::Signature::Types::Bases::Class.new(location: nil)
          when Instance
            Ruby::Signature::Types::Bases::Instance.new(location: nil)
          when Self
            Ruby::Signature::Types::Bases::Self.new(location: nil)
          when Top
            Ruby::Signature::Types::Bases::Top.new(location: nil)
          when Bot
            Ruby::Signature::Types::Bases::Bottom.new(location: nil)
          when Boolean
            Ruby::Signature::Types::Bases::Bool.new(location: nil)
          when Void
            Ruby::Signature::Types::Bases::Void.new(location: nil)
          when Nil
            Ruby::Signature::Types::Bases::Nil.new(location: nil)
          when Var
            Ruby::Signature::Types::Variable.new(name: type.name, location: nil)
          when Name::Class
            Ruby::Signature::Types::ClassSingleton.new(name: type_name_1(type.name), location: nil)
          when Name::Instance
            Ruby::Signature::Types::ClassInstance.new(
              name: type_name_1(type.name),
              args: type.args.map {|arg| type_1(arg) },
              location: nil
            )
          when Name::Interface
            Ruby::Signature::Types::Interface.new(
              name: type_name_1(type.name),
              args: type.args.map {|arg| type_1(arg) },
              location: nil
            )
          when Name::Alias
            type.args.empty? or raise "alias type with args is not supported"
            Ruby::Signature::Types::Alias.new(name: type_name_1(type.name), location: nil)
          when Union
            Ruby::Signature::Types::Union.new(
              types: type.types.map {|ty| type_1(ty) },
              location: nil
            )
          when Intersection
            Ruby::Signature::Types::Intersection.new(
              types: type.types.map {|ty| type_1(ty) },
              location: nil
            )
          when Literal
            Ruby::Signature::Types::Literal.new(literal: type.value, location: nil)
          when Tuple
            Ruby::Signature::Types::Tuple.new(
              types: type.types.map {|ty| type_1(ty) },
              location: nil
            )
          when Record
            fields = type.elements.each.with_object({}) do |(key, value), hash|
              hash[key] = type_1(value)
            end
            Ruby::Signature::Types::Record.new(fields: fields, location: nil)
          when Proc
            Ruby::Signature::Types::Proc.new(
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
          Ruby::Signature::TypeName.new(name: name.name, namespace: namespace_1(name.namespace))
        end

        def namespace(namespace)
          Namespace.parse(namespace.to_s)
        end

        def namespace_1(namespace)
          Ruby::Signature::Namespace.parse(namespace.to_s)
        end

        def function_1(params, return_type)
          Ruby::Signature::Types::Function.new(
            required_positionals: params.required.map {|type| Ruby::Signature::Types::Function::Param.new(name: nil, type: type_1(type)) },
            optional_positionals: params.optional.map {|type| Ruby::Signature::Types::Function::Param.new(name: nil, type: type_1(type)) },
            rest_positionals: params.rest&.yield_self {|type| Ruby::Signature::Types::Function::Param.new(name: nil, type: type_1(type)) },
            trailing_positionals: [],
            required_keywords: params.required_keywords.transform_values {|type| Ruby::Signature::Types::Function::Param.new(name: nil, type: type_1(type)) },
            optional_keywords: params.optional_keywords.transform_values {|type| Ruby::Signature::Types::Function::Param.new(name: nil, type: type_1(type)) },
            rest_keywords: params.rest_keywords&.yield_self {|type| Ruby::Signature::Types::Function::Param.new(name: nil, type: type_1(type)) },
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

        def method_type(method_type)
          case method_type
          when Ruby::Signature::MethodType
            type = Interface::MethodType.new(
              type_params: method_type.type_params,
              return_type: type(method_type.type.return_type),
              params: params(method_type.type),
              location: nil,
              block: method_type.block&.yield_self do |block|
                Interface::Block.new(
                  optional: !block.required,
                  type: Proc.new(params: params(block.type), return_type: type(block.type.return_type), location: nil)
                )
              end
            )

            if block_given?
              yield type
            else
              type
            end
          when :any
            :any
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
            decl = definition_builder.env.find_alias(type_name) or raise "Unknown type name: #{type_name}"
            type(definition_builder.env.absolute_type(decl.type, namespace: type_name.namespace))
          end
        end

        def interface(type, private:, self_type: type)
          case type
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
                    method_type(type) {|ty| ty.subst(subst) }
                  end
                )
              end
            end

          when Name::Interface
            Interface::Interface.new(type: self_type, private: private).tap do |interface|
              type_name = type_name_1(type.name)
              decl = definition_builder.env.find_class(type_name)
              definition = definition_builder.build_interface(type_name, decl)

              subst = Interface::Substitution.build(
                definition.type_params,
                type.args,
                self_type: self_type
              )

              definition.methods.each do |name, method|
                interface.methods[name] = Interface::Interface::Combination.overload(
                  method.method_types.map do |type|
                    method_type(type) {|type| type.subst(subst) }
                  end
                )
              end
            end

          when Name::Class, Name::Module
            Interface::Interface.new(type: self_type, private: private).tap do |interface|
              definition = definition_builder.build_singleton(type_name_1(type.name))

              instance_type = Name::Instance.new(name: type.name,
                                                 args: definition.declaration.type_params.map {Any.new(location: nil)},
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
                    method_type(type) {|type| type.subst(subst) }
                  end
                )
              end
            end

          when Literal
            interface type.back_type, private: private, self_type: self_type

          when Nil
            interface Builtin::NilClass.instance_type, private: private, self_type: self_type

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
                    } + aref.types
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
                    } + update.types
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
                    } + ref.types
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
                    } + update.types
                  )
                end
              end
            end

          else
            raise "Unexpected type for interface: #{type}"
          end
        end

        def absolute_type(type, namespace:)
          definition_builder.env.absolute_type(type_1(type), namespace: namespace_1(namespace)) do |type|
            type.name.absolute!
          end
        end

        def absolute_type_name(type_name, namespace:)
          definition_builder.env.absolute_type_name(type_name_1(type_name), namespace: namespace_1(namespace)) do |name|
            name.absolute!
          end
        end
      end
    end
  end
end
