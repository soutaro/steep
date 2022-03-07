module Steep
  module AST
    module Types
      class Factory
        attr_reader :definition_builder

        attr_reader :type_name_cache
        attr_reader :type_cache

        attr_reader :type_interface_cache

        def initialize(builder:)
          @definition_builder = builder

          @type_name_cache = {}
          @type_cache = {}
          @type_interface_cache = {}
        end

        def type_name_resolver
          @type_name_resolver ||= RBS::TypeNameResolver.from_env(definition_builder.env)
        end

        def type_opt(type)
          if type
            type(type)
          end
        end

        def type(type)
          ty = type_cache[type] and return ty

          type_cache[type] =
            case type
            when RBS::Types::Bases::Any
              Any.new(location: type.location)
            when RBS::Types::Bases::Class
              Class.new(location: type.location)
            when RBS::Types::Bases::Instance
              Instance.new(location: type.location)
            when RBS::Types::Bases::Self
              Self.new(location: type.location)
            when RBS::Types::Bases::Top
              Top.new(location: type.location)
            when RBS::Types::Bases::Bottom
              Bot.new(location: type.location)
            when RBS::Types::Bases::Bool
              Boolean.new(location: type.location)
            when RBS::Types::Bases::Void
              Void.new(location: type.location)
            when RBS::Types::Bases::Nil
              Nil.new(location: type.location)
            when RBS::Types::Variable
              Var.new(name: type.name, location: type.location)
            when RBS::Types::ClassSingleton
              type_name = type.name
              Name::Singleton.new(name: type_name, location: type.location)
            when RBS::Types::ClassInstance
              type_name = type.name
              args = type.args.map {|arg| type(arg) }
              Name::Instance.new(name: type_name, args: args, location: type.location)
            when RBS::Types::Interface
              type_name = type.name
              args = type.args.map {|arg| type(arg) }
              Name::Interface.new(name: type_name, args: args, location: type.location)
            when RBS::Types::Alias
              type_name = type.name
              args = type.args.map {|arg| type(arg) }
              Name::Alias.new(name: type_name, args: args, location: type.location)
            when RBS::Types::Union
              Union.build(types: type.types.map {|ty| type(ty) }, location: type.location)
            when RBS::Types::Intersection
              Intersection.build(types: type.types.map {|ty| type(ty) }, location: type.location)
            when RBS::Types::Optional
              Union.build(types: [type(type.type), Nil.new(location: nil)], location: type.location)
            when RBS::Types::Literal
              Literal.new(value: type.literal, location: type.location)
            when RBS::Types::Tuple
              Tuple.new(types: type.types.map {|ty| type(ty) }, location: type.location)
            when RBS::Types::Record
              elements = type.fields.each.with_object({}) do |(key, value), hash|
                hash[key] = type(value)
              end
              Record.new(elements: elements, location: type.location)
            when RBS::Types::Proc
              func = Interface::Function.new(
                params: params(type.type),
                return_type: type(type.type.return_type),
                location: type.location
              )
              block = if type.block
                        Interface::Block.new(
                          type: Interface::Function.new(
                            params: params(type.block.type),
                            return_type: type(type.block.type.return_type),
                            location: type.location
                          ),
                          optional: !type.block.required
                        )
                      end

              Proc.new(type: func, block: block)
            else
              raise "Unexpected type given: #{type}"
            end
        end

        def type_1(type)
          case type
          when Any
            RBS::Types::Bases::Any.new(location: type.location)
          when Class
            RBS::Types::Bases::Class.new(location: type.location)
          when Instance
            RBS::Types::Bases::Instance.new(location: type.location)
          when Self
            RBS::Types::Bases::Self.new(location: type.location)
          when Top
            RBS::Types::Bases::Top.new(location: type.location)
          when Bot
            RBS::Types::Bases::Bottom.new(location: type.location)
          when Boolean
            RBS::Types::Bases::Bool.new(location: type.location)
          when Void
            RBS::Types::Bases::Void.new(location: type.location)
          when Nil
            RBS::Types::Bases::Nil.new(location: type.location)
          when Var
            RBS::Types::Variable.new(name: type.name, location: type.location)
          when Name::Singleton
            RBS::Types::ClassSingleton.new(name: type.name, location: type.location)
          when Name::Instance
            RBS::Types::ClassInstance.new(
              name: type.name,
              args: type.args.map {|arg| type_1(arg) },
              location: type.location
            )
          when Name::Interface
            RBS::Types::Interface.new(
              name: type.name,
              args: type.args.map {|arg| type_1(arg) },
              location: type.location
            )
          when Name::Alias
            RBS::Types::Alias.new(
              name: type.name,
              args: type.args.map {|arg| type_1(arg) },
              location: type.location
            )
          when Union
            RBS::Types::Union.new(
              types: type.types.map {|ty| type_1(ty) },
              location: type.location
            )
          when Intersection
            RBS::Types::Intersection.new(
              types: type.types.map {|ty| type_1(ty) },
              location: type.location
            )
          when Literal
            RBS::Types::Literal.new(literal: type.value, location: type.location)
          when Tuple
            RBS::Types::Tuple.new(
              types: type.types.map {|ty| type_1(ty) },
              location: type.location
            )
          when Record
            fields = type.elements.each.with_object({}) do |(key, value), hash|
              hash[key] = type_1(value)
            end
            RBS::Types::Record.new(fields: fields, location: type.location)
          when Proc
            block = if type.block
                      RBS::Types::Block.new(
                        type: function_1(type.block.type),
                        required: !type.block.optional?
                      )
                    end
            RBS::Types::Proc.new(
              type: function_1(type.type),
              block: block,
              location: type.location
            )
          when Logic::Base
            RBS::Types::Bases::Bool.new(location: type.location)
          else
            raise "Unexpected type given: #{type} (#{type.class})"
          end
        end

        def function_1(func)
          params = func.params
          return_type = func.return_type

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
          Interface::Function::Params.build(
            required: type.required_positionals.map {|param| type(param.type) },
            optional: type.optional_positionals.map {|param| type(param.type) },
            rest: type.rest_positionals&.yield_self {|param| type(param.type) },
            required_keywords: type.required_keywords.transform_values {|param| type(param.type) },
            optional_keywords: type.optional_keywords.transform_values {|param| type(param.type) },
            rest_keywords: type.rest_keywords&.yield_self {|param| type(param.type) }
          )
        end

        def type_param(type_param)
          Interface::TypeParam.new(
            name: type_param.name,
            upper_bound: type_param.upper_bound&.yield_self {|u| type(u) },
            variance: type_param.variance,
            unchecked: type_param.unchecked?
          )
        end

        def type_param_1(type_param)
          RBS::AST::TypeParam.new(
            name: type_param.name,
            variance: type_param.variance,
            upper_bound: type_param.upper_bound&.yield_self {|u| type_1(u) },
            location: type_param.location
          ).unchecked!(type_param.unchecked)
        end

        def method_type(method_type, self_type:, subst2: nil, method_decls:)
          fvs = self_type.free_variables()

          type_params = []
          conflicting_names = []

          type_params = method_type.type_params.map do |type_param|
            if fvs.include?(type_param.name)
              conflicting_names << type_param.name
            end

            type_param(type_param)
          end

          type_params, subst = Interface::TypeParam.rename(type_params, conflicting_names)
          subst.merge!(subst2, overwrite: true) if subst2

          type =
            Interface::MethodType.new(
              type_params: type_params,
              type: Interface::Function.new(
                params: params(method_type.type).subst(subst),
                return_type: type(method_type.type.return_type).subst(subst),
                location: method_type.location
              ),
              block: method_type.block&.yield_self do |block|
                Interface::Block.new(
                  optional: !block.required,
                  type: Interface::Function.new(
                    params: params(block.type).subst(subst),
                    return_type: type(block.type.return_type).subst(subst),
                    location: nil
                  )
                )
              end,
              method_decls: method_decls
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

          conflicting_names = method_type.type_params.each.with_object([]) do |param, names|
            names << params.name if fvs.include?(param.name)
          end

          type_params, subst = Interface::TypeParam.rename(method_type.type_params, conflicting_names)

          type = RBS::MethodType.new(
            type_params: type_params.map {|param| type_param_1(param) },
            type: function_1(method_type.type.subst(subst)),
            block: method_type.block&.yield_self do |block|
              block_type = block.type.subst(subst)

              RBS::Types::Block.new(
                type: function_1(block_type),
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

        def unfold(type_name, args)
          type(
            definition_builder.expand_alias2(
              type_name,
              args.empty? ? args : args.map {|t| type_1(t) }
            )
          )
        end

        def expand_alias(type)
          unfolded = case type
                     when AST::Types::Name::Alias
                       unfold(type.name, type.args)
                     else
                       type
                     end

          if block_given?
            yield unfolded
          else
            unfolded
          end
        end

        def deep_expand_alias(type, recursive: Set.new, &block)
          raise "Recursive type definition: #{type}" if recursive.member?(type)

          ty = case type
               when AST::Types::Name::Alias
                 deep_expand_alias(expand_alias(type), recursive: recursive.union([type]))
               when AST::Types::Union
                 AST::Types::Union.build(
                   types: type.types.map {|ty| deep_expand_alias(ty, recursive: recursive, &block) },
                   location: type.location
                 )
               else
                 type
               end

          if block_given?
            yield ty
          else
            ty
          end
        end

        def flatten_union(type, acc = [])
          case type
          when AST::Types::Union
            type.types.each {|ty| flatten_union(ty, acc) }
          else
            acc << type
          end

          acc
        end

        def unwrap_optional(type)
          case type
          when AST::Types::Union
            falsy_types, truthy_types = type.types.partition do |type|
              (type.is_a?(AST::Types::Literal) && type.value == false) ||
                type.is_a?(AST::Types::Nil)
            end

            [
              AST::Types::Union.build(types: truthy_types),
              AST::Types::Union.build(types: falsy_types)
            ]
          when AST::Types::Name::Alias
            unwrap_optional(expand_alias(type))
          when AST::Types::Boolean
            [type, type]
          else
            [type, nil]
          end
        end

        NilClassName = TypeName("::NilClass")

        def setup_primitives(method_name, method_def, method_type)
          defined_in = method_def.defined_in
          member = method_def.member

          if member.is_a?(RBS::AST::Members::MethodDefinition)
            case method_name
            when :is_a?, :kind_of?, :instance_of?
              if defined_in == RBS::BuiltinNames::Object.name && member.instance?
                return method_type.with(
                  type: method_type.type.with(
                    return_type: AST::Types::Logic::ReceiverIsArg.new(location: method_type.type.return_type.location)
                  )
                )
              end

            when :nil?
              case defined_in
              when RBS::BuiltinNames::Object.name,
                NilClassName
                return method_type.with(
                  type: method_type.type.with(
                    return_type: AST::Types::Logic::ReceiverIsNil.new(location: method_type.type.return_type.location)
                  )
                )
              end

            when :!
              case defined_in
              when RBS::BuiltinNames::BasicObject.name,
                RBS::BuiltinNames::TrueClass.name,
                RBS::BuiltinNames::FalseClass.name
                return method_type.with(
                  type: method_type.type.with(
                    return_type: AST::Types::Logic::Not.new(location: method_type.type.return_type.location)
                  )
                )
              end

            when :===
              case defined_in
              when RBS::BuiltinNames::Module.name
                return method_type.with(
                  type: method_type.type.with(
                    return_type: AST::Types::Logic::ArgIsReceiver.new(location: method_type.type.return_type.location)
                  )
                )
              when RBS::BuiltinNames::Object.name, RBS::BuiltinNames::String.name, RBS::BuiltinNames::Integer.name, RBS::BuiltinNames::Symbol.name,
                RBS::BuiltinNames::TrueClass.name, RBS::BuiltinNames::FalseClass.name, TypeName("::NilClass")
                # Value based type-case works on literal types which is available for String, Integer, Symbol, TrueClass, FalseClass, and NilClass
                return method_type.with(
                  type: method_type.type.with(
                    return_type: AST::Types::Logic::ArgEqualsReceiver.new(location: method_type.type.return_type.location)
                  )
                )
              end
            end
          end

          method_type
        end

        def interface(type, private:, self_type: type)
          Steep.logger.debug { "Factory#interface: #{type}, private=#{private}, self_type=#{self_type}" }

          cache_key = [type, self_type, private]
          if type_interface_cache.key?(cache_key)
            return type_interface_cache[cache_key]
          end

          case type
          when Name::Alias
            interface(expand_alias(type), private: private, self_type: self_type)

          when Self
            if self_type != type
              interface self_type, private: private, self_type: Self.new
            else
              raise "Unexpected `self` type interface"
            end

          when Name::Instance
            Interface::Interface.new(type: self_type, private: private).tap do |interface|
              definition = definition_builder.build_instance(type.name)

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
                Steep.logger.tagged "method = #{name}" do
                  next if method.private? && !private

                  interface.methods[name] = Interface::Interface::Entry.new(
                    method_types: method.defs.map do |type_def|
                      method_name = InstanceMethodName.new(type_name: type_def.implemented_in || type_def.defined_in, method_name: name)
                      decl = TypeInference::MethodCall::MethodDecl.new(method_name: method_name, method_def: type_def)
                      setup_primitives(
                        name,
                        type_def,
                        method_type(type_def.type,
                                    method_decls: Set[decl],
                                    self_type: self_type,
                                    subst2: subst)
                      )
                    end
                  )
                end
              end
            end

          when Name::Interface
            Interface::Interface.new(type: self_type, private: private).tap do |interface|
              type_name = type.name
              definition = definition_builder.build_interface(type_name)

              subst = Interface::Substitution.build(
                definition.type_params,
                type.args,
                self_type: self_type
              )

              definition.methods.each do |name, method|
                interface.methods[name] = Interface::Interface::Entry.new(
                  method_types: method.defs.map do |type_def|
                    decls = Set[TypeInference::MethodCall::MethodDecl.new(
                      method_name: InstanceMethodName.new(type_name: type_def.implemented_in || type_def.defined_in, method_name: name),
                      method_def: type_def
                    )]
                    method_type(type_def.type, method_decls: decls, self_type: self_type, subst2: subst)
                  end
                )
              end
            end

          when Name::Singleton
            Interface::Interface.new(type: self_type, private: private).tap do |interface|
              definition = definition_builder.build_singleton(type.name)

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

                interface.methods[name] = Interface::Interface::Entry.new(
                  method_types: method.defs.map do |type_def|
                    decl = TypeInference::MethodCall::MethodDecl.new(
                      method_name: SingletonMethodName.new(type_name: type_def.implemented_in || type_def.defined_in,
                                                           method_name: name),
                      method_def: type_def
                    )
                    setup_primitives(
                      name,
                      type_def,
                      method_type(type_def.type,
                                  method_decls: Set[decl],
                                  self_type: self_type,
                                  subst2: subst)
                    )
                  end
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
                    types1 = interface1.methods[name].method_types
                    types2 = interface2.methods[name].method_types

                    if types1 == types2
                      interface.methods[name] = interface1.methods[name]
                    else
                      method_types = {}

                      types1.each do |type1|
                        types2.each do |type2|
                          type = type1 | type2 or next
                          method_types[type] = true
                        end
                      end

                      unless method_types.empty?
                        interface.methods[name] = Interface::Interface::Entry.new(method_types: method_types.keys)
                      end
                    end
                  end
                end
              end
            end

          when Intersection
            yield_self do
              interfaces = type.types.map {|ty| interface(ty, private: private, self_type: self_type) }
              interfaces.inject do |interface1, interface2|
                Interface::Interface.new(type: self_type, private: private).tap do |interface|
                  interface.methods.merge!(interface1.methods)
                  interface.methods.merge!(interface2.methods)
                end
              end
            end

          when Tuple
            yield_self do
              element_type = Union.build(types: type.types, location: nil)
              array_type = Builtin::Array.instance_type(element_type)
              interface(array_type, private: private, self_type: self_type).tap do |array_interface|
                array_interface.methods[:[]] = array_interface.methods[:[]].yield_self do |aref|
                  Interface::Interface::Entry.new(
                    method_types: type.types.map.with_index {|elem_type, index|
                      Interface::MethodType.new(
                        type_params: [],
                        type: Interface::Function.new(
                          params: Interface::Function::Params.build(required: [AST::Types::Literal.new(value: index)]),
                          return_type: elem_type,
                          location: nil
                        ),
                        block: nil,
                        method_decls: Set[]
                      )
                    } + aref.method_types
                  )
                end

                array_interface.methods[:[]=] = array_interface.methods[:[]=].yield_self do |update|
                  Interface::Interface::Entry.new(
                    method_types: type.types.map.with_index {|elem_type, index|
                      Interface::MethodType.new(
                        type_params: [],
                        type: Interface::Function.new(
                          params: Interface::Function::Params.build(required: [AST::Types::Literal.new(value: index), elem_type]),
                          return_type: elem_type,
                          location: nil
                        ),
                        block: nil,
                        method_decls: Set[]
                      )
                    } + update.method_types
                  )
                end

                array_interface.methods[:first] = array_interface.methods[:first].yield_self do |first|
                  Interface::Interface::Entry.new(
                    method_types: [
                      Interface::MethodType.new(
                        type_params: [],
                        type: Interface::Function.new(
                          params: Interface::Function::Params.empty,
                          return_type: type.types[0] || AST::Builtin.nil_type,
                          location: nil
                        ),
                        block: nil,
                        method_decls: Set[]
                      )
                    ]
                  )
                end

                array_interface.methods[:last] = array_interface.methods[:last].yield_self do |last|
                  Interface::Interface::Entry.new(
                    method_types: [
                      Interface::MethodType.new(
                        type_params: [],
                        type: Interface::Function.new(
                          params: Interface::Function::Params.empty,
                          return_type: type.types.last || AST::Builtin.nil_type,
                          location: nil
                        ),
                        block: nil,
                        method_decls: Set[]
                      )
                    ]
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
                  Interface::Interface::Entry.new(
                    method_types: type.elements.map {|key_value, value_type|
                      key_type = Literal.new(value: key_value, location: nil)

                      Interface::MethodType.new(
                        type_params: [],
                        type: Interface::Function.new(
                          params: Interface::Function::Params.build(
                            required: [key_type],
                            optional: [],
                            rest: nil,
                            required_keywords: {},
                            optional_keywords: {},
                            rest_keywords: nil
                          ),
                          return_type: value_type,
                          location: nil
                        ),
                        block: nil,
                        method_decls: Set[]
                      )
                    } + ref.method_types
                  )
                end

                hash_interface.methods[:[]=] = hash_interface.methods[:[]=].yield_self do |update|
                  Interface::Interface::Entry.new(
                    method_types: type.elements.map {|key_value, value_type|
                      key_type = Literal.new(value: key_value, location: nil)
                      Interface::MethodType.new(
                        type_params: [],
                        type: Interface::Function.new(
                          params: Interface::Function::Params.build(
                            required: [key_type, value_type],
                            optional: [],
                            rest: nil,
                            required_keywords: {},
                            optional_keywords: {},
                            rest_keywords: nil
                          ),
                          return_type: value_type,
                          location: nil),
                        block: nil,
                        method_decls: Set[]
                      )
                    } + update.method_types
                  )
                end
              end
            end

          when Proc
            interface(Builtin::Proc.instance_type, private: private, self_type: self_type).tap do |interface|
              method_type = Interface::MethodType.new(
                type_params: [],
                type: type.type,
                block: type.block,
                method_decls: Set[]
              )

              interface.methods[:call] = Interface::Interface::Entry.new(method_types: [method_type])

              if type.block_required?
                interface.methods.delete(:[])
              else
                interface.methods[:[]] = Interface::Interface::Entry.new(method_types: [method_type.with(block: nil)])
              end
            end

          when Logic::Base
            interface(AST::Builtin.bool_type, private: private, self_type: self_type)

          else
            raise "Unexpected type for interface: #{type}"
          end.tap do |interface|
            type_interface_cache[cache_key] = interface
          end
        end

        def module_name?(type_name)
          entry = env.class_decls[type_name] and entry.is_a?(RBS::Environment::ModuleEntry)
        end

        def class_name?(type_name)
          entry = env.class_decls[type_name] and entry.is_a?(RBS::Environment::ClassEntry)
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
          type_name_resolver.resolve(type_name, context: namespace.ascend)
        end

        def instance_type(type_name, args: nil, location: nil)
          raise unless type_name.class?

          definition = definition_builder.build_singleton(type_name)
          def_args = definition.type_params.map { Any.new(location: nil) }

          if args
            raise if def_args.size != args.size
          else
            args = def_args
          end

          AST::Types::Name::Instance.new(location: location, name: type_name, args: args)
        end
      end
    end
  end
end
