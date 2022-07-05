module Steep
  module Services
    module HoverProvider
      class Ruby
        TypeContent = Struct.new(:node, :type, :location, keyword_init: true)
        VariableContent = Struct.new(:node, :name, :type, :location, keyword_init: true)
        MethodCallContent = Struct.new(:node, :method_call, :location, keyword_init: true)
        DefinitionContent = Struct.new(:node, :method_name, :method_type, :definition, :location, keyword_init: true)
        ConstantContent = Struct.new(:location, :full_name, :type, :decl, keyword_init: true) do
          def comments
            case
            when class_or_module?
              decl.decls.filter_map {|d| d.decl.comment }
            when constant?
              [decl.decl.comment]
            else
              []
            end.compact
          end

          def constant?
            decl.is_a?(::RBS::Environment::SingleEntry)
          end

          def class_or_module?
            decl.is_a?(::RBS::Environment::MultiEntry)
          end
        end

        attr_reader :service

        def initialize(service:)
          @service = service
        end

        def project
          service.project
        end

        def method_definition_for(factory, type_name, singleton_method: nil, instance_method: nil)
          case
          when instance_method
            factory.definition_builder.build_instance(type_name).methods[instance_method]
          when singleton_method
            methods = factory.definition_builder.build_singleton(type_name).methods

            if singleton_method == :new
              methods[:new] || methods[:initialize]
            else
              methods[singleton_method]
            end
          else
            raise "One of the instance_method or singleton_method is required"
          end
        end

        def typecheck(target, path:, content:, line:, column:)
          subtyping = service.signature_services[target.name].current_subtyping or return
          source = Source.parse(content, path: path, factory: subtyping.factory)
          source = source.without_unrelated_defs(line: line, column: column)
          Services::TypeCheckService.type_check(source: source, subtyping: subtyping)
        rescue
          nil
        end

        def method_name_from_method(context, builder:)
          defined_in = context.method.defined_in
          method_name = context.name

          case
          when defined_in.class?
            case
            when builder.build_instance(defined_in).methods.key?(method_name)
              InstanceMethodName.new(type_name: defined_in, method_name: method_name)
            when builder.build_singleton(defined_in).methods.key?(method_name)
              SingletonMethodName.new(type_name: defined_in, method_name: method_name)
            end
          else
            InstanceMethodName.new(type_name: defined_in, method_name: method_name)
          end
        end

        def content_for(target:, path:, line:, column:)
          file = service.source_files[path]
          typing = typecheck(target, path: path, content: file.content, line: line, column: column) or return
          node, *parents = typing.source.find_nodes(line: line, column: column)

          if node
            case node.type
            when :lvar
              var_name = node.children[0]
              context = typing.context_at(line: line, column: column)
              var_type = context.type_env[var_name] || AST::Types::Any.new(location: nil)

              return VariableContent.new(node: node, name: var_name, type: var_type, location: node.location.name)

            when :lvasgn
              var_name, rhs = node.children
              context = typing.context_at(line: line, column: column)
              type = context.type_env[var_name] || typing.type_of(node: rhs)

              return VariableContent.new(node: node, name: var_name, type: type, location: node.location.name)

            when :send, :csend
              result_node =
                case parents[0]&.type
                when :block, :numblock
                  if node == parents[0].children[0]
                    parents[0]
                  else
                    node
                  end
                else
                  node
                end

              case call = typing.call_of(node: result_node)
              when TypeInference::MethodCall::Typed, TypeInference::MethodCall::Error
                unless call.method_decls.empty?
                  return MethodCallContent.new(
                    node: result_node,
                    method_call: call,
                    location: node.location.selector
                  )
                end
              end

            when :def, :defs
              context = typing.context_at(line: line, column: column)
              method_context = context.method_context

              if method_context && method_context.method
                return DefinitionContent.new(
                  node: node,
                  method_name: method_name_from_method(method_context, builder: context.factory.definition_builder),
                  method_type: method_context.method_type,
                  definition: method_context.method,
                  location: node.loc.name
                )
              end

            when :const, :casgn
              context = typing.context_at(line: line, column: column)

              type = typing.type_of(node: node)
              const_name = typing.source_index.reference(constant_node: node)

              if const_name
                decl = context.env.class_decls[const_name] || context.env.constant_decls[const_name]

                return ConstantContent.new(
                  location: node.location.name,
                  full_name: const_name,
                  type: type,
                  decl: decl
                )
              end
            end

            TypeContent.new(
              node: node,
              type: typing.type_of(node: node),
              location: node.location.expression
            )
          end
        end
      end
    end
  end
end
