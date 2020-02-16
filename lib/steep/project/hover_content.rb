module Steep
  class Project
    class HoverContent
      TypeContent = Struct.new(:node, :type, :location, keyword_init: true)
      VariableContent = Struct.new(:node, :name, :type, :location, keyword_init: true)
      MethodCallContent = Struct.new(:node, :method_name, :type, :location, keyword_init: true)

      InstanceMethodName = Struct.new(:class_name, :method_name)
      SingletonMethodName = Struct.new(:class_name, :method_name)

      attr_reader :project

      def initialize(project:)
        @project = project
      end

      def content_for(path:, line:, column:)
        source_file = project.targets.map {|target| target.source_files[path] }.compact[0]

        if source_file
          case (status = source_file.status)
          when SourceFile::TypeCheckStatus
            node, *parents = status.source.find_nodes(line: line, column: column)

            if node
              case node.type
              when :lvar, :lvasgn
                var_name = node.children[0]
                context = status.typing.context_of(node: node)
                var_type = context.type_env.get(lvar: var_name.name)

                VariableContent.new(node: node, name: var_name.name, type: var_type, location: node.location.name)
              when :send
                receiver, name, *_ = node.children
                receiver_type = if receiver
                                  status.typing.type_of(node: receiver)
                                else
                                  status.typing.context_of(node: node).self_type
                                end

                method_name = case receiver_type
                              when AST::Types::Name::Instance
                                InstanceMethodName.new(receiver_type.name, name)
                              when AST::Types::Name::Class
                                SingletonMethodName.new(receiver_type.name, name)
                              else
                                nil
                              end

                MethodCallContent.new(
                  node: node,
                  method_name: method_name,
                  type: status.typing.type_of(node: node),
                  location: node.location.expression
                )
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
