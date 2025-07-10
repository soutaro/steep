module Steep
  module Services
    module HoverProvider

      class Ruby
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
            factory.definition_builder.build_instance(type_name).methods.fetch(instance_method)
          when singleton_method
            methods = factory.definition_builder.build_singleton(type_name).methods

            if singleton_method == :new
              methods[:new] || methods.fetch(:initialize)
            else
              methods.fetch(singleton_method)
            end
          else
            raise "One of the instance_method or singleton_method is required"
          end
        end

        def typecheck(target, path:, content:, line:, column:)
          subtyping = service.signature_services.fetch(target.name).current_subtyping or return
          source = Source.parse(content, path: path, factory: subtyping.factory)
          source = source.without_unrelated_defs(line: line, column: column)
          resolver = ::RBS::Resolver::ConstantResolver.new(builder: subtyping.factory.definition_builder)
          pos = source.buffer.loc_to_pos([line, column])
          [
            Services::TypeCheckService.type_check(source: source, subtyping: subtyping, constant_resolver: resolver, cursor: pos),
            subtyping
          ]
        rescue
          nil
        end

        def method_name_from_method(context, builder:)
          context.method or raise
          defined_in = context.method.defined_in or raise
          method_name = context.name or raise

          case
          when defined_in.class?
            case
            when builder.build_instance(defined_in).methods.key?(method_name)
              InstanceMethodName.new(type_name: defined_in, method_name: method_name)
            when builder.build_singleton(defined_in).methods.key?(method_name)
              SingletonMethodName.new(type_name: defined_in, method_name: method_name)
            else
              raise
            end
          else
            InstanceMethodName.new(type_name: defined_in, method_name: method_name)
          end
        end

        def content_for(target:, path:, line:, column:)
          file = service.source_files[path] or return
          (typing, subtyping = typecheck(target, path: path, content: file.content, line: line, column: column)) or return
          locator = Locator::Ruby.new(typing.source)
          result = locator.find(line, column)

          case result
          when Locator::NodeResult
            node = result.node
            parents = result.parents

            case node.type
            when :lvar
              var_name = node.children[0]
              context = typing.cursor_context.context or raise
              var_type = context.type_env[var_name] || AST::Types::Any.instance()

              return VariableContent.new(
                node: node,
                name: var_name,
                type: var_type,
                location: node.location.name # steep:ignore NoMethod
              )

            when :lvasgn
              var_name, _rhs = node.children
              context = typing.cursor_context.context or raise
              type = context.type_env[var_name] || typing.type_of(node: node)

              return VariableContent.new(
                node: node,
                name: var_name,
                type: type,
                location: node.location.name # steep:ignore NoMethod
              )

            when :send, :csend
              result_node =
                case parents[0]&.type
                when :block, :numblock
                  if node == parents.fetch(0).children[0]
                    parents.fetch(0)
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
                    location: node.location.selector # steep:ignore NoMethod
                  )
                end
              end

            when :def, :defs
              context = typing.cursor_context.context or raise
              method_context = context.method_context

              if method_context && method_context.method
                if method_context.method_type
                  return DefinitionContent.new(
                    node: node,
                    method_name: method_name_from_method(method_context, builder: context.factory.definition_builder),
                    method_type: method_context.method_type,
                    definition: method_context.method,
                    location: node.loc.name # steep:ignore NoMethod
                  )
                end
              end

            when :const, :casgn
              context = typing.cursor_context.context or raise

              type = typing.type_of(node: node)
              const_name = typing.source_index.reference(constant_node: node)

              if const_name
                entry = context.env.constant_entry(const_name) or return

                return ConstantContent.new(
                  location: node.location.name, # steep:ignore NoMethod
                  full_name: const_name,
                  type: type,
                  decl: entry
                )
              end
            end

            TypeContent.new(
              node: node,
              type: typing.type_of(node: node),
              location: node.location.expression
            )

          when Locator::TypeAssertionResult
            context = typing.cursor_context.context or raise
            pos = typing.source.buffer.loc_to_pos([line, column])

            nesting = context.module_context.nesting
            type_vars = context.variable_context.type_params.map { _1.name }

            if (name, location = result.locate_type_name(pos, nesting, subtyping, type_vars))
              if content = type_name_content(subtyping.factory.env, name, location)
                return content
              end
            end

            assertion_node = result.node.node
            original_node = assertion_node.children[0] or raise

            original_type = typing.type_of(node: original_node)
            asserted_type = typing.type_of(node: assertion_node)

            if original_type != asserted_type
              TypeAssertionContent.new(
                node: assertion_node,
                original_type: original_type,
                asserted_type: asserted_type,
                location: assertion_node.location.expression
              )
            else
              TypeContent.new(
                node: assertion_node,
                type: typing.type_of(node: assertion_node),
                location: assertion_node.location.expression
              )
            end

          when Locator::TypeApplicationResult
            begin
              context = typing.cursor_context.context or raise
              pos = typing.source.buffer.loc_to_pos([line, column])

              nesting = context.module_context.nesting
              type_vars = context.variable_context.type_params.map { _1.name }

              if (name, location = result.locate_type_name(pos, nesting, subtyping, type_vars))
                if content = type_name_content(subtyping.factory.env, name, location)
                  return content
                end
              end

              nil
            rescue ::RBS::ParsingError
              return nil
            end
          end
        end

        def type_name_content(environment, type_name, location)
          case
          when type_name.class?
            if entry = environment.module_class_entry(type_name)
              decl = case entry
              when ::RBS::Environment::ModuleEntry, ::RBS::Environment::ClassEntry
                entry.primary_decl
              else
                entry.decl
              end

              ClassTypeContent.new(
                location: location,
                decl: decl
              )
            end
          when type_name.interface?
            if entry = environment.interface_decls.fetch(type_name, nil)
              InterfaceTypeContent.new(
                location: location,
                decl: entry.decl
              )
            end
          when type_name.alias?
            if entry = environment.type_alias_decls.fetch(type_name, nil)
              TypeAliasContent.new(
                location: location,
                decl: entry.decl
              )
            end
          end
        end

        def content_for_inline(target:, path:, line:, column:)
          signature = service.signature_services.fetch(target.name)
          source = signature.latest_env.sources.find do
            if _1.is_a?(::RBS::Source::Ruby)
              _1.buffer.name == path
            end
          end

          return unless source.is_a?(::RBS::Source::Ruby)

          locator = Locator::Inline.new(source)
          result = locator.find(line, column)

          case result
          when Locator::InlineTypeNameResult
            return type_name_content(signature.latest_env, result.type_name, result.location)
          else
            Steep.logger.fatal { { result: result.class }.inspect }
          end

          # file = service.source_files[path] or return

          # (typing, subtyping = typecheck(target, path: path, content: file.content, line: line, column: column)) or return
          # locator = Locator::Ruby.new(typing.source)
          # result = locator.find(line, column)

          nil
        end
      end
    end
  end
end
