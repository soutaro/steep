module Steep
  class Project
    class HoverContent
      TypeContent = Struct.new(:node, :type, :location, keyword_init: true)
      VariableContent = Struct.new(:node, :name, :type, :location, keyword_init: true)
      MethodCallContent = Struct.new(:node, :method_name, :type, :definition, :location, keyword_init: true)
      DefinitionContent = Struct.new(:node, :method_name, :method_type, :definition, :location, keyword_init: true) do
        def comment_string
          if comments = definition&.comments
            comments.map(&:string).join("\n----\n")
          end
        end
      end

      InstanceMethodName = Struct.new(:class_name, :method_name)
      SingletonMethodName = Struct.new(:class_name, :method_name)

      attr_reader :project

      def initialize(project:)
        @project = project
      end

      def method_definition_for(factory, module_name, singleton_method: nil, instance_method: nil)
        type_name = factory.type_name_1(module_name)

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
        end
      end

      def content_for(path:, line:, column:)
        target = project.targets.find {|target| target.source_file?(path) }

        if target
          source_file = target.source_files[path]
          target.type_check(target_sources: [source_file], validate_signatures: false)

          case (status = source_file.status)
          when SourceFile::TypeCheckStatus
            node, *parents = status.source.find_nodes(line: line, column: column)

            if node
              case node.type
              when :lvar
                var_name = node.children[0]
                context = status.typing.context_at(line: line, column: column)
                var_type = context.lvar_env[var_name.name] || AST::Types::Any.new(location: nil)

                VariableContent.new(node: node, name: var_name.name, type: var_type, location: node.location.name)
              when :lvasgn
                var_name, rhs = node.children
                context = status.typing.context_at(line: line, column: column)
                type = context.lvar_env[var_name.name] || status.typing.type_of(node: rhs)

                VariableContent.new(node: node, name: var_name.name, type: type, location: node.location.name)
              when :send
                receiver, method_name, *_ = node.children


                result_node = if parents[0]&.type == :block
                                parents[0]
                              else
                                node
                              end

                context = status.typing.context_at(line: line, column: column)

                receiver_type = if receiver
                                  status.typing.type_of(node: receiver)
                                else
                                  context.self_type
                                end

                factory = context.type_env.subtyping.factory
                method_name, definition = case receiver_type
                                          when AST::Types::Name::Instance
                                            method_definition = method_definition_for(factory, receiver_type.name, instance_method: method_name)
                                            if method_definition&.defined_in
                                              owner_name = factory.type_name(method_definition.defined_in)
                                              [
                                                InstanceMethodName.new(owner_name, method_name),
                                                method_definition
                                              ]
                                            end
                                          when AST::Types::Name::Class
                                            method_definition = method_definition_for(factory, receiver_type.name, singleton_method: method_name)
                                            if method_definition&.defined_in
                                              owner_name = factory.type_name(method_definition.defined_in)
                                              [
                                                SingletonMethodName.new(owner_name, method_name),
                                                method_definition
                                              ]
                                            end
                                          else
                                            nil
                                          end

                MethodCallContent.new(
                  node: node,
                  method_name: method_name,
                  type: status.typing.type_of(node: result_node),
                  definition: definition,
                  location: result_node.location.expression
                )
              when :def, :defs
                context = status.typing.context_at(line: line, column: column)
                method_context = context.method_context

                if method_context && method_context.method
                  DefinitionContent.new(
                    node: node,
                    method_name: method_context.name,
                    method_type: method_context.method_type,
                    definition: method_context.method,
                    location: node.loc.expression
                  )
                end
              else
                type = status.typing.type_of(node: node)

                TypeContent.new(
                  node: node,
                  type: type,
                  location: node.location.expression
                )
              end
            end
          end
        end
      end
    end
  end
end
