module Steep
  module Services
    class HoverContent
      TypeContent = Struct.new(:node, :type, :location, keyword_init: true)
      VariableContent = Struct.new(:node, :name, :type, :location, keyword_init: true)
      MethodCallContent = Struct.new(:node, :method_name, :type, :definition, :location, keyword_init: true)
      DefinitionContent = Struct.new(:node, :method_name, :method_type, :definition, :location, keyword_init: true) do
      TypeAliasContent = Struct.new(:location, :decl, keyword_init: true)
      ClassContent = Struct.new(:location, :decl, keyword_init: true)
      InterfaceContent = Struct.new(:location, :decl, keyword_init: true)

        def comment_string
          if comments = definition&.comments
            comments.map {|c| c.string.chomp }.uniq.join("\n----\n")
          end
        end
      end

      InstanceMethodName = Struct.new(:class_name, :method_name)
      SingletonMethodName = Struct.new(:class_name, :method_name)

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

      def content_for(path:, line:, column:)
        case
        when target = project.target_for_source_path(path)
          Steep.logger.info "target #{target}"

          hover_for_source(column, line, path, target)
        when (_, targets = project.targets_for_path(path))
          target = targets[0]
          return unless target
          service = self.service.signature_services[target.name]
          _buffer, decls = service.latest_env.buffers_decls.find do |buffer, _|
            Pathname(buffer.name) == path
          end

          locator = RBS::Locator.new(decls: decls)
          hd, tail = locator.find2(line: line, column: column)

          case type = tail[0]
          when RBS::Types::Alias
            env = service.latest_env
            alias_decl = env.alias_decls[type.name]&.decl or raise

            location = tail[0].location
            TypeAliasContent.new(
              location: location,
              decl: alias_decl
            )
          when RBS::Types::ClassInstance, RBS::Types::ClassSingleton
            if hd == :name
              env = service.latest_env
              class_decl = env.class_decls[type.name]&.decls[0]&.decl or raise
              location = tail[0].location[:name]
              ClassContent.new(
                location: location,
                decl: class_decl
              )
            end
          when RBS::Types::Interface
            env = service.latest_env
            interface_decl = env.interface_decls[type.name]&.decl or raise
            location = type.location[:name]

            InterfaceContent.new(
              location: location,
              decl: interface_decl
            )
          end
        end
      end

      def hover_for_source(column, line, path, target)
        file = service.source_files[path]
        typing = typecheck(target, path: path, content: file.content, line: line, column: column) or return
        node, *parents = typing.source.find_nodes(line: line, column: column)

        if node
          case node.type
          when :lvar
            var_name = node.children[0]
            context = typing.context_at(line: line, column: column)
            var_type = context.lvar_env[var_name] || AST::Types::Any.new(location: nil)

            VariableContent.new(node: node, name: var_name, type: var_type, location: node.location.name)
          when :lvasgn
            var_name, rhs = node.children
            context = typing.context_at(line: line, column: column)
            type = context.lvar_env[var_name] || typing.type_of(node: rhs)

            VariableContent.new(node: node, name: var_name, type: type, location: node.location.name)
          when :send
            receiver, method_name, *_ = node.children


            result_node = if parents[0]&.type == :block
                            parents[0]
                          else
                            node
                          end

            context = typing.context_at(line: line, column: column)

            receiver_type = if receiver
                              typing.type_of(node: receiver)
                            else
                              context.self_type
                            end

            factory = context.type_env.subtyping.factory
            method_name, definition = case receiver_type
                                      when AST::Types::Name::Instance
                                        method_definition = method_definition_for(factory, receiver_type.name, instance_method: method_name)
                                        if method_definition&.defined_in
                                          owner_name = method_definition.defined_in
                                          [
                                            InstanceMethodName.new(owner_name, method_name),
                                            method_definition
                                          ]
                                        end
                                      when AST::Types::Name::Singleton
                                        method_definition = method_definition_for(factory, receiver_type.name, singleton_method: method_name)
                                        if method_definition&.defined_in
                                          owner_name = method_definition.defined_in
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
              type: typing.type_of(node: result_node),
              definition: definition,
              location: result_node.location.expression
            )
          when :def, :defs
            context = typing.context_at(line: line, column: column)
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
            type = typing.type_of(node: node)

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
