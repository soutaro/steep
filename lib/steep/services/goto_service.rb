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

      class ConstantQuery < Struct.new(:name, :from, keyword_init: true)
        include SourceHelper
      end
      class MethodQuery < Struct.new(:name, :from, keyword_init: true)
        include SourceHelper
      end
      class TypeNameQuery < Struct.new(:name, keyword_init: true)
      end

      attr_reader :type_check, :assignment

      def initialize(type_check:, assignment:)
        @type_check = type_check
        @assignment = assignment
      end

      def project
        type_check.project
      end

      def implementation(path:, line:, column:)
        locations = [] #: Array[loc]

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
        locations = [] #: Array[loc]

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

      def type_definition(path:, line:, column:)
        locations = [] #: Array[loc]

        relative_path = project.relative_path(path)

        target = type_check.source_file?(relative_path) or return []
        source = type_check.source_files[relative_path]
        typing, signature = type_check_path(target: target, path: relative_path, content: source.content, line: line, column: column)

        typing or return []
        signature or return []

        node, *_parents = typing.source.find_nodes(line: line, column: column)
        node or return []

        type = typing.type_of(node: node)

        subtyping = signature.current_subtyping or return []

        each_type_name(type).uniq.each do |name|
          type_name_locations(name, locations: locations)
        end

        locations.uniq.select do |loc|
          case loc
          when RBS::Location
            assignment =~ loc.name
          else
            true
          end
        end
      end

      def each_type_name(type, &block)
        if block
          case type
          when AST::Types::Name::Instance, AST::Types::Name::Alias, AST::Types::Name::Singleton, AST::Types::Name::Interface
            yield type.name
          when AST::Types::Literal
            yield type.back_type.name
          when AST::Types::Nil
            yield RBS::TypeName.new(name: :NilClass, namespace: RBS::Namespace.root)
          when AST::Types::Boolean
            yield RBS::BuiltinNames::TrueClass.name
            yield RBS::BuiltinNames::FalseClass.name
          end

          type.each_child do |child|
            each_type_name(child, &block)
          end
        else
          enum_for :each_type_name, type
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
        queries = [] #: Array[query]

        relative_path = project.relative_path(path)

        case
        when target = type_check.source_file?(relative_path)
          source = type_check.source_files[relative_path]
          typing, _signature = type_check_path(target: target, path: relative_path, content: source.content, line: line, column: column)
          if typing
            node, *parents = typing.source.find_nodes(line: line, column: column)

            if node && parents
              case node.type
              when :const, :casgn
                named_location = (_ = node.location) #: Parser::AST::_NamedLocation
                if test_ast_location(named_location.name, line: line, column: column)
                  if name = typing.source_index.reference(constant_node: node)
                    queries << ConstantQuery.new(name: name, from: :ruby)
                  end
                end
              when :def, :defs
                named_location = (_ = node.location) #: Parser::AST::_NamedLocation
                if test_ast_location(named_location.name, line: line, column: column)
                  if method_context = typing.context_at(line: line, column: column).method_context
                    if method = method_context.method
                      method.defs.each do |defn|
                        singleton_method =
                          case defn.member
                          when RBS::AST::Members::MethodDefinition
                            defn.member.singleton?
                          when RBS::AST::Members::Attribute
                            defn.member.kind == :singleton
                          end

                        name =
                          if singleton_method
                            SingletonMethodName.new(type_name: defn.defined_in, method_name: method_context.name)
                          else
                            InstanceMethodName.new(type_name: defn.defined_in, method_name: method_context.name)
                          end

                        queries << MethodQuery.new(name: name, from: :ruby)
                      end
                    end
                  end
                end
              when :send
                location = (_ = node.location) #: Parser::AST::_SelectorLocation
                if test_ast_location(location.selector, line: line, column: column)
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
        when target_names = type_check.signature_file?(path) #: Array[Symbol]
          target_names.each do |target_name|
            signature_service = type_check.signature_services[target_name] #: SignatureService

            env = signature_service.latest_env
            buffer = env.buffers.find {|buf| buf.name.to_s == relative_path.to_s } or raise
            (dirs, decls = env.signatures[buffer]) or raise

            locator = RBS::Locator.new(buffer: buffer, dirs: dirs, decls: decls)
            last, nodes = locator.find2(line: line, column: column)

            nodes or raise

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
                parent_node = nodes[1] #: RBS::AST::Declarations::Class | RBS::AST::Declarations::Module | RBS::AST::Declarations::Interface
                type_name = parent_node.name
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
        resolver = RBS::Resolver::ConstantResolver.new(builder: subtyping.factory.definition_builder)
        [
          Services::TypeCheckService.type_check(source: source, subtyping: subtyping, constant_resolver: resolver),
          signature_service
        ]
      rescue
        nil
      end

      def constant_definition_in_rbs(name, locations:)
        type_check.signature_services.each_value do |signature|
          env = signature.latest_env #: RBS::Environment

          case entry = env.constant_entry(name)
          when RBS::Environment::ConstantEntry
            if entry.decl.location
              locations << entry.decl.location[:name]
            end
          when RBS::Environment::ClassEntry, RBS::Environment::ModuleEntry
            entry.decls.each do |d|
              if d.decl.location
                locations << d.decl.location[:name]
              end
            end
          when RBS::Environment::ClassAliasEntry, RBS::Environment::ModuleAliasEntry
            if entry.decl.location
              locations << entry.decl.location[:new_name]
            end
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
                if decl.location
                  locations << decl.location[:name]
                end
              when RBS::AST::Members::Alias
                if decl.location
                  locations << decl.location[:new_name]
                end
              when RBS::AST::Members::AttrAccessor, RBS::AST::Members::AttrReader, RBS::AST::Members::AttrWriter
                if decl.location
                  locations << decl.location[:name]
                end
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
            case decl
            when RBS::AST::Declarations::Class, RBS::AST::Declarations::Module, RBS::AST::Declarations::Interface, RBS::AST::Declarations::TypeAlias
              if decl.location
                locations << decl.location[:name]
              end
            when RBS::AST::Declarations::AliasDecl
              if decl.location
                locations << decl.location[:new_name]
              end
            else
              raise
            end
          end
        end

        locations
      end
    end
  end
end
