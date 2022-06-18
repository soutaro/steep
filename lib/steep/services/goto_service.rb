module Steep
  module Services
    class GotoService
      include ModuleHelper

      module SourceHelper
        def from_ruby?
          from == :ruby
        end

        def from_rbs?
          from == :rbs
        end
      end

      ConstantQuery = Struct.new(:name, :from, keyword_init: true) do
        include SourceHelper
      end
      MethodQuery = Struct.new(:name, :from, keyword_init: true) do
        include SourceHelper
      end
      TypeNameQuery = Struct.new(:name, keyword_init: true)

      attr_reader :type_check, :assignment

      def initialize(type_check:, assignment:)
        @type_check = type_check
        @assignment = assignment
      end

      def project
        type_check.project
      end

      def implementation(path:, line:, column:)
        locations = []

        # relative_path = project.relative_path(path)

        queries = query_at(path: path, line: line, column: column)
        queries.uniq!

        queries.each do |query|
          case query
          when ConstantQuery
            constant_definition_in_ruby(query.name, locations: locations)
          when MethodQuery
            method_locations(query.name, locations: locations, in_ruby: true, in_rbs: false)
          when TypeNameQuery
            type_name_locations(query.name, locations: locations)
          end
        end

        locations.uniq
      end

      def definition(path:, line:, column:)
        locations = []

        queries = query_at(path: path, line: line, column: column)
        queries.uniq!

        queries.each do |query|
          case query
          when ConstantQuery
            constant_definition_in_rbs(query.name, locations: locations) if query.from_ruby?
            constant_definition_in_ruby(query.name, locations: locations) if query.from_rbs?
          when MethodQuery
            method_locations(
              query.name,
              locations: locations,
              in_ruby: query.from_rbs?,
              in_rbs: query.from_ruby?
            )
          when TypeNameQuery
            type_name_locations(query.name, locations: locations)
          end
        end

        # Drop un-assigned paths here.
        # The path assignment makes sense only for `.rbs` files, because un-assigned `.rb` files are already skipped since they are not type checked.
        #
        locations.uniq.select do |loc|
          case loc
          when RBS::Location
            assignment =~ loc.name
          else
            true
          end
        end
      end

      def test_ast_location(loc, line:, column:)
        return false if line < loc.line
        return false if line == loc.line && column < loc.column
        return false if loc.last_line < line
        return false if line == loc.last_line && loc.last_column < column
        true
      end

      def query_at(path:, line:, column:)
        queries = []

        relative_path = project.relative_path(path)

        case
        when target = type_check.source_file?(relative_path)
          source = type_check.source_files[relative_path]
          typing, _signature = type_check_path(target: target, path: relative_path, content: source.content, line: line, column: column)
          if typing
            node, *parents = typing.source.find_nodes(line: line, column: column)

            if node
              case node.type
              when :const, :casgn
                if test_ast_location(node.location.name, line: line, column: column)
                  if name = typing.source_index.reference(constant_node: node)
                    queries << ConstantQuery.new(name: name, from: :ruby)
                  end
                end
              when :def, :defs
                if test_ast_location(node.location.name, line: line, column: column)
                  if method_context = typing.context_at(line: line, column: column).method_context
                    type_name = method_context.method.defined_in
                    name =
                      if method_context.method.defs.any? {|defn| defn.member.singleton? }
                        SingletonMethodName.new(type_name: type_name, method_name: method_context.name)
                      else
                        InstanceMethodName.new(type_name: type_name, method_name: method_context.name)
                      end
                    queries << MethodQuery.new(name: name, from: :ruby)
                  end
                end
              when :send
                if test_ast_location(node.location.selector, line: line, column: column)
                  if (parent = parents[0]) && parent.type == :block && parent.children[0] == node
                    node = parents[0]
                  end

                  case call = typing.call_of(node: node)
                  when TypeInference::MethodCall::Typed, TypeInference::MethodCall::Error
                    call.method_decls.each do |decl|
                      queries << MethodQuery.new(name: decl.method_name, from: :ruby)
                    end
                  when TypeInference::MethodCall::Untyped
                    # nop
                  when TypeInference::MethodCall::NoMethodError
                    # nop
                  end
                end
              end
            end
          end
        when target_names = type_check.signature_file?(path)
          target_names.each do |target_name|
            signature_service = type_check.signature_services[target_name]
            decls = signature_service.latest_env.declarations.select do |decl|
              buffer_path = Pathname(decl.location.buffer.name)
              buffer_path == relative_path || buffer_path == path
            end

            locator = RBS::Locator.new(decls: decls)
            last, nodes = locator.find2(line: line, column: column)
            case nodes[0]
            when RBS::AST::Declarations::Class, RBS::AST::Declarations::Module
              if last == :name
                queries << ConstantQuery.new(name: nodes[0].name, from: :rbs)
              end
            when RBS::AST::Declarations::Constant
              if last == :name
                queries << ConstantQuery.new(name: nodes[0].name, from: :rbs)
              end
            when RBS::AST::Members::MethodDefinition
              if last == :name
                type_name = nodes[1].name
                method_name = nodes[0].name
                if nodes[0].instance?
                  queries << MethodQuery.new(
                    name: InstanceMethodName.new(type_name: type_name, method_name: method_name),
                    from: :rbs
                  )
                end
                if nodes[0].singleton?
                  queries << MethodQuery.new(
                    name: SingletonMethodName.new(type_name: type_name, method_name: method_name),
                    from: :rbs
                  )
                end
              end
            when RBS::AST::Members::Include, RBS::AST::Members::Extend, RBS::AST::Members::Prepend
              if last == :name
                queries << TypeNameQuery.new(name: nodes[0].name)
              end
            when RBS::Types::ClassInstance, RBS::Types::ClassSingleton, RBS::Types::Interface, RBS::Types::Alias
              if last == :name
                queries << TypeNameQuery.new(name: nodes[0].name)
              end
            when RBS::AST::Declarations::Class::Super, RBS::AST::Declarations::Module::Self
              if last == :name
                queries << TypeNameQuery.new(name: nodes[0].name)
              end
            end
          end
        end

        queries
      end

      def type_check_path(target:, path:, content:, line:, column:)
        signature_service = type_check.signature_services[target.name]
        subtyping = signature_service.current_subtyping or return
        source = Source.parse(content, path: path, factory: subtyping.factory)
        source = source.without_unrelated_defs(line: line, column: column)
        [
          Services::TypeCheckService.type_check(source: source, subtyping: subtyping),
          signature_service
        ]
      rescue
        nil
      end

      def constant_definition_in_rbs(name, locations:)
        type_check.signature_services.each_value do |signature|
          env = signature.latest_env

          if entry = env.class_decls[name]
            entry.decls.each do |d|
              locations << d.decl.location[:name]
            end
          end

          if entry = env.constant_decls[name]
            locations << entry.decl.location[:name]
          end
        end

        locations
      end

      def constant_definition_in_ruby(name, locations:)
        type_check.source_files.each do |path, source|
          if typing = source.typing
            entry = typing.source_index.entry(constant: name)
            entry.definitions.each do |node|
              case node.type
              when :const
                locations << node.location.expression
              when :casgn
                parent = node.children[0]
                location =
                  if parent
                    parent.location.expression.join(node.location.name)
                  else
                    node.location.name
                  end
                locations << location
              end
            end
          end
        end

        locations
      end

      def method_locations(name, in_ruby:, in_rbs:, locations:)
        if in_ruby
          type_check.source_files.each do |path, source|
            if typing = source.typing
              entry = typing.source_index.entry(method: name)

              if entry.definitions.empty?
                if name.is_a?(SingletonMethodName) && name.method_name == :new
                  initialize = InstanceMethodName.new(method_name: :initialize, type_name: name.type_name)
                  entry = typing.source_index.entry(method: initialize)
                end
              end

              entry.definitions.each do |node|
                case node.type
                when :def
                  locations << node.location.name
                when :defs
                  locations << node.location.name
                end
              end
            end
          end
        end

        if in_rbs
          type_check.signature_services.each_value do |signature|
            index = signature.latest_rbs_index

            entry = index.entry(method_name: name)

            if entry.declarations.empty?
              if name.is_a?(SingletonMethodName) && name.method_name == :new
                initialize = InstanceMethodName.new(method_name: :initialize, type_name: name.type_name)
                entry = index.entry(method_name: initialize)
              end
            end

            entry.declarations.each do |decl|
              case decl
              when RBS::AST::Members::MethodDefinition
                locations << decl.location[:name]
              when RBS::AST::Members::Alias
                locations << decl.location[:new_name]
              when RBS::AST::Members::AttrAccessor, RBS::AST::Members::AttrReader, RBS::AST::Members::AttrWriter
                locations << decl.location[:name]
              end
            end
          end
        end

        locations
      end

      def type_name_locations(name, locations: [])
        type_check.signature_services.each_value do |signature|
          index = signature.latest_rbs_index

          entry = index.entry(type_name: name)
          entry.declarations.each do |decl|
            locations << decl.location[:name]
          end
        end

        locations
      end
    end
  end
end
