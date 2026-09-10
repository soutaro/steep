module Steep
  module Services
    class SymbolProvider
      Result = _ = Struct.new(:constant, :type_name, :method_names, :type, keyword_init: true)

      attr_reader :service

      def initialize(service:)
        @service = service
      end

      def project
        service.project
      end

      def symbols_at(path:, line:, column:)
        result = Result.new(constant: nil, type_name: nil, method_names: [], type: nil)

        relative_path = project.relative_path(path)

        case
        when target = project.target_for_inline_source_path(relative_path)
          inline_symbols(target, relative_path, line: line, column: column, result: result)

          unless result.type_name
            ruby_symbols(target, relative_path, line: line, column: column, result: result)
          end
        when target = project.target_for_source_path(relative_path)
          ruby_symbols(target, relative_path, line: line, column: column, result: result)
        when target_names = service.signature_file?(path)
          target_names.each do |target_name|
            rbs_symbols(target_name, relative_path, line: line, column: column, result: result)
          end
        end

        result.method_names.uniq!

        result
      end

      private

      def ruby_symbols(target, path, line:, column:, result:)
        source = service.source_files.fetch(path, nil) or return
        typing, subtyping = type_check(target, path: path, content: source.content, line: line, column: column) || return

        locator = Locator::Ruby.new(typing.source)

        case located = locator.find(line, column)
        when Locator::NodeResult
          node = located.node
          parents = located.parents

          case node.type
          when :const, :casgn
            named_location = (_ = node.location) #: Parser::AST::_NamedLocation
            if cursor_in?(named_location.name, line: line, column: column)
              result.constant = typing.source_index.reference(constant_node: node)
            end
          when :def, :defs
            named_location = (_ = node.location) #: Parser::AST::_NamedLocation
            if cursor_in?(named_location.name, line: line, column: column)
              if method_context = typing.cursor_context.context&.method_context
                if method = method_context.method
                  method.defs.each do |defn|
                    singleton_method =
                      case defn.member
                      when RBS::AST::Members::MethodDefinition
                        defn.member.singleton?
                      when RBS::AST::Members::Attribute
                        defn.member.kind == :singleton
                      end

                    result.method_names <<
                      if singleton_method
                        SingletonMethodName.new(type_name: defn.defined_in, method_name: method_context.name)
                      else
                        InstanceMethodName.new(type_name: defn.defined_in, method_name: method_context.name)
                      end
                  end
                end
              end
            end
          when :send
            location = (_ = node.location) #: Parser::AST::_SelectorLocation
            if cursor_in?(location.selector, line: line, column: column)
              if (parent = parents[0]) && (parent.type == :block || parent.type == :numblock || parent.type == :itblock) && parent.children[0] === node
                node = parent
              end

              case call = typing.call_of(node: node)
              when TypeInference::MethodCall::Typed, TypeInference::MethodCall::Error
                call.method_decls.each do |decl|
                  result.method_names << decl.method_name
                end
              end
            end
          end
        when Locator::TypeAssertionResult, Locator::TypeApplicationResult
          context = typing.cursor_context.context or raise
          nesting = context.module_context.nesting
          type_vars = context.variable_context.type_params.map(&:name)
          pos = typing.source.buffer.loc_to_pos([line, column])

          if pair = located.locate_type_name(pos, nesting, subtyping, type_vars)
            result.type_name = pair[0]
          end
        end

        node, *_parents = typing.source.find_nodes(line: line, column: column)
        if node && typing.has_type?(node)
          result.type = rbs_type(subtyping, typing.type_of(node: node))
        end
      end

      def inline_symbols(target, path, line:, column:, result:)
        signature_service = service.signature_services.fetch(target.name)

        source = signature_service.latest_env.sources.find do |source|
          source.is_a?(RBS::Source::Ruby) && source.buffer.name == path
        end

        if source.is_a?(RBS::Source::Ruby)
          case located = Locator::Inline.new(source).find(line, column)
          when Locator::InlineTypeNameResult
            result.type_name = located.type_name
          end
        end
      end

      def rbs_symbols(target_name, path, line:, column:, result:)
        signature_service = service.signature_services.fetch(target_name)

        env = signature_service.latest_env
        source = env.each_rbs_source.find {|source| source.buffer.name == path } or return

        locator = RBS::Locator.new(buffer: source.buffer, dirs: source.directives, decls: source.declarations)
        last, nodes = locator.find2(line: line, column: column)
        nodes or return

        return unless last == :name

        case node = nodes[0]
        when RBS::AST::Declarations::Class, RBS::AST::Declarations::Module, RBS::AST::Declarations::Constant
          result.constant = node.name
        when RBS::AST::Members::MethodDefinition
          parent = nodes[1] #: RBS::AST::Declarations::Class | RBS::AST::Declarations::Module | RBS::AST::Declarations::Interface
          if node.instance?
            result.method_names << InstanceMethodName.new(type_name: parent.name, method_name: node.name)
          end
          if node.singleton?
            result.method_names << SingletonMethodName.new(type_name: parent.name, method_name: node.name)
          end
        when RBS::AST::Members::Include, RBS::AST::Members::Extend, RBS::AST::Members::Prepend,
             RBS::Types::ClassInstance, RBS::Types::ClassSingleton, RBS::Types::Interface, RBS::Types::Alias,
             RBS::AST::Declarations::Class::Super, RBS::AST::Declarations::Module::Self
          result.type_name = node.name
        end
      end

      def type_check(target, path:, content:, line:, column:)
        subtyping = service.signature_services.fetch(target.name).current_subtyping or return
        source = Source.parse(content, path: path, factory: subtyping.factory)
        source = source.without_unrelated_defs(line: line, column: column)
        resolver = RBS::Resolver::ConstantResolver.new(builder: subtyping.factory.definition_builder)
        pos = source.buffer.loc_to_pos([line, column])
        [
          Services::TypeCheckService.type_check(source: source, subtyping: subtyping, constant_resolver: resolver, cursor: pos),
          subtyping
        ]
      rescue
        nil
      end

      def rbs_type(subtyping, type)
        subtyping.factory.type_1(type)
      rescue
        nil
      end

      def cursor_in?(location, line:, column:)
        return false unless location
        return false if line < location.line
        return false if line == location.line && column < location.column
        return false if location.last_line < line
        return false if line == location.last_line && location.last_column < column
        true
      end
    end
  end
end
