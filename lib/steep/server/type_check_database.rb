module Steep
  module Server
    class TypeCheckDatabase
      Entry =
        _ = Struct.new(:name, :kind, :role, :source, :start_line, :start_character, :end_line, :end_character, keyword_init: true) do
          # @implements Entry

          def lsp_range
            {
              start: { line: start_line, character: start_character },
              end: { line: end_line, character: end_character }
            }
          end

          def to_wire
            [name, KIND_CODES.fetch(kind), ROLE_CODES.fetch(role), SOURCE_CODES.fetch(source), start_line, start_character, end_line, end_character]
          end

          def self.from_wire(array)
            Entry.new(
              name: array[0],
              kind: KINDS.fetch(array[1]),
              role: ROLES.fetch(array[2]),
              source: SOURCES.fetch(array[3]),
              start_line: array[4],
              start_character: array[5],
              end_line: array[6],
              end_character: array[7]
            )
          end
        end

      class NamePool
        def initialize
          @ids = {}
          @names = {}
          @counts = {}
          @next_id = 0
        end

        def intern(name)
          if id = @ids.fetch(name, nil)
            @counts[id] = @counts.fetch(id) + 1
            id
          else
            id = @next_id
            @next_id += 1
            @ids[name] = id
            @names[id] = name
            @counts[id] = 1
            id
          end
        end

        def release(id)
          count = @counts.fetch(id) - 1
          if count.zero?
            name = @names.delete(id) or raise
            @ids.delete(name)
            @counts.delete(id)
          else
            @counts[id] = count
          end
        end

        def [](id)
          @names.fetch(id, nil)
        end

        def id_of(name)
          @ids.fetch(name, nil)
        end

        def size
          @ids.size
        end
      end

      FileData = _ = Struct.new(:diagnostics, :entries, keyword_init: true)

      KIND_CODES = { constant: 0, method: 1, interface: 2, type_alias: 3, global: 4 } #: Hash[Entry::kind, Integer]
      ROLE_CODES = { definition: 0, reference: 1 } #: Hash[Entry::role, Integer]
      SOURCE_CODES = { ruby: 0, rbs: 1 } #: Hash[Entry::source, Integer]

      KINDS = KIND_CODES.invert #: Hash[Integer, Entry::kind]
      ROLES = ROLE_CODES.invert #: Hash[Integer, Entry::role]
      SOURCES = SOURCE_CODES.invert #: Hash[Integer, Entry::source]

      ENTRY_SIZE = 8

      def self.entries_from(typing)
        entries = [] #: Array[Entry]
        seen = Set[] #: Set[Array[untyped]]

        index = typing.source_index

        index.constant_index.each do |name, entry|
          entry.definitions.each do |node|
            if location = constant_definition_location(node)
              push_entry(entries, seen, name: name.to_s, kind: :constant, role: :definition, location: location)
            end
          end
          entry.references.each do |node|
            push_entry(entries, seen, name: name.to_s, kind: :constant, role: :reference, location: node.location.expression)
          end
        end

        index.method_index.each do |name, entry|
          entry.definitions.each do |node|
            location = (_ = node.location).name #: Parser::Source::Range
            push_entry(entries, seen, name: name.to_s, kind: :method, role: :definition, location: location)
          end
        end

        typing.method_calls.each do |node, call|
          decls =
            case call
            when TypeInference::MethodCall::Typed, TypeInference::MethodCall::Error
              call.method_decls
            end
          next unless decls

          location = method_call_location(node) or next
          decls.each do |decl|
            push_entry(entries, seen, name: decl.method_name.to_s, kind: :method, role: :reference, location: location)
          end
        end

        entries
      end

      def self.constant_definition_location(node)
        case node.type
        when :const
          node.location.expression #: Parser::Source::Range
        when :casgn
          name_location = (_ = node.location).name #: Parser::Source::Range
          if parent = node.children[0]
            parent_location = parent.location.expression #: Parser::Source::Range
            parent_location.join(name_location)
          else
            name_location
          end
        end
      end

      def self.method_call_location(node)
        case node.type
        when :block, :numblock, :itblock
          method_call_location(node.children.fetch(0))
        else
          location = node.location
          selector = location.respond_to?(:selector) ? (_ = location).selector : nil #: Parser::Source::Range?
          selector || location.expression
        end
      end

      def self.push_entry(entries, seen, name:, kind:, role:, location:)
        key = [name, kind, role, location.line, location.column, location.last_line, location.last_column] #: Array[untyped]
        return if seen.include?(key)
        seen << key

        entries << Entry.new(
          name: name,
          kind: kind,
          role: role,
          source: :ruby,
          start_line: location.line - 1,
          start_character: location.column,
          end_line: location.last_line - 1,
          end_character: location.last_column
        )
      end

      def self.rbs_entries_by_path(index)
        entries = {} #: Hash[Pathname, Array[Entry]]
        seen = Set[] #: Set[Array[untyped]]

        index.type_index.each do |type_name, entry|
          kind =
            case
            when type_name.interface?
              :interface
            when type_name.alias?
              :type_alias
            else
              :constant
            end #: Entry::kind

          entry.declarations.each do |decl|
            location = rbs_declaration_location(decl) or next
            push_rbs_entry(entries, seen, name: type_name.to_s, kind: kind, location: location)
          end
        end

        index.method_index.each do |method_name, entry|
          entry.declarations.each do |decl|
            location = rbs_declaration_location(decl) or next
            push_rbs_entry(entries, seen, name: method_name.to_s, kind: :method, location: location)
          end
        end

        index.const_index.each do |const_name, entry|
          entry.declarations.each do |decl|
            location = rbs_declaration_location(decl) or next
            push_rbs_entry(entries, seen, name: const_name.to_s, kind: :constant, location: location)
          end
        end

        index.global_index.each do |global_name, entry|
          entry.declarations.each do |decl|
            location = rbs_declaration_location(decl) or next
            push_rbs_entry(entries, seen, name: global_name.to_s, kind: :global, location: location)
          end
        end

        entries
      end

      def self.rbs_declaration_location(decl)
        case decl
        when RBS::AST::Declarations::Class, RBS::AST::Declarations::Module, RBS::AST::Declarations::Interface, RBS::AST::Declarations::TypeAlias,
             RBS::AST::Declarations::Constant, RBS::AST::Declarations::Global,
             RBS::AST::Members::MethodDefinition, RBS::AST::Members::AttrAccessor, RBS::AST::Members::AttrReader, RBS::AST::Members::AttrWriter
          if (location = decl.location) && location.key?(:name)
            location[:name]
          end
        when RBS::AST::Declarations::ClassAlias, RBS::AST::Declarations::ModuleAlias, RBS::AST::Members::Alias
          if (location = decl.location) && location.key?(:new_name)
            location[:new_name]
          end
        when RBS::AST::Ruby::Declarations::ClassDecl, RBS::AST::Ruby::Declarations::ModuleDecl, RBS::AST::Ruby::Declarations::ClassModuleAliasDecl,
             RBS::AST::Ruby::Declarations::ConstantDecl, RBS::AST::Ruby::Members::DefMember
          decl.name_location
        end
      end

      def self.push_rbs_entry(entries, seen, name:, kind:, location:)
        path = Pathname(location.buffer.name)
        key = [path, name, kind, location.start_line, location.start_column, location.end_line, location.end_column] #: Array[untyped]
        return if seen.include?(key)
        seen << key

        (entries[path] ||= []) << Entry.new(
          name: name,
          kind: kind,
          role: :definition,
          source: :rbs,
          start_line: location.start_line - 1,
          start_character: location.start_column,
          end_line: location.end_line - 1,
          end_character: location.end_column
        )
      end

      attr_reader :pool

      def initialize
        @files = {}
        @pool = NamePool.new
        @name_paths = {}
      end

      def update(path:, target:, diagnostics:, entries:)
        targets = (@files[path] ||= {})

        if old = targets.fetch(target, nil)
          release_entries(path, old.entries)
        end

        packed = [] #: Array[Integer]
        entries.each do |entry|
          id = pool.intern(entry.name)
          track_name(id, path)
          packed << id << KIND_CODES.fetch(entry.kind) << ROLE_CODES.fetch(entry.role) << SOURCE_CODES.fetch(entry.source) <<
            entry.start_line << entry.start_character << entry.end_line << entry.end_character
        end

        targets[target] = FileData.new(diagnostics: diagnostics, entries: packed)
      end

      def remove(path)
        if targets = @files.delete(path)
          targets.each_value do |data|
            release_entries(path, data.entries)
          end
        end
      end

      def checked?(path)
        @files.key?(path)
      end

      def diagnostics_of(path)
        targets = @files.fetch(path, nil) or return nil

        merged = nil #: Array[untyped]?
        targets.each_value do |data|
          if diagnostics = data.diagnostics
            if merged
              merged.concat(diagnostics)
            else
              merged = diagnostics.dup
            end
          end
        end

        merged&.uniq!
        merged
      end

      def each_diagnostics(&block)
        if block
          @files.each_key do |path|
            if diagnostics = diagnostics_of(path)
              yield [path, diagnostics]
            end
          end
        else
          enum_for :each_diagnostics
        end
      end

      def definitions(name:, kind: nil)
        matching_entries(name: name, role: :definition, kind: kind)
      end

      def references(name:, kind: nil)
        matching_entries(name: name, role: :reference, kind: kind)
      end

      def entry_count
        count = 0
        @files.each_value do |targets|
          targets.each_value do |data|
            count += data.entries.size / ENTRY_SIZE
          end
        end
        count
      end

      private

      def matching_entries(name:, role:, kind:)
        id = pool.id_of(name) or return []
        name_paths = @name_paths.fetch(id, nil) or return []

        role_code = ROLE_CODES.fetch(role)
        kind_code = kind ? KIND_CODES.fetch(kind) : nil

        results = [] #: Array[[Pathname, Entry]]
        seen = Set[] #: Set[[Pathname, Array[Integer]]]

        name_paths.each_key do |path|
          @files.fetch(path).each_value do |data|
            array = data.entries
            index = 0
            while index < array.size
              if array.fetch(index) == id && array.fetch(index + 2) == role_code && (kind_code.nil? || array.fetch(index + 1) == kind_code)
                key = array[index, ENTRY_SIZE] or raise
                unless seen.include?([path, key])
                  seen << [path, key]
                  results << [path, unpack_entry(array, index)]
                end
              end
              index += ENTRY_SIZE
            end
          end
        end

        results
      end

      def unpack_entry(array, index)
        Entry.new(
          name: pool[array.fetch(index)] || raise,
          kind: KINDS.fetch(array.fetch(index + 1)),
          role: ROLES.fetch(array.fetch(index + 2)),
          source: SOURCES.fetch(array.fetch(index + 3)),
          start_line: array.fetch(index + 4),
          start_character: array.fetch(index + 5),
          end_line: array.fetch(index + 6),
          end_character: array.fetch(index + 7)
        )
      end

      def release_entries(path, array)
        index = 0
        while index < array.size
          id = array.fetch(index)
          untrack_name(id, path)
          pool.release(id)
          index += ENTRY_SIZE
        end
      end

      def track_name(id, path)
        counts = (@name_paths[id] ||= {})
        counts[path] = counts.fetch(path, 0) + 1
      end

      def untrack_name(id, path)
        counts = @name_paths.fetch(id)
        count = counts.fetch(path) - 1
        if count.zero?
          counts.delete(path)
          @name_paths.delete(id) if counts.empty?
        else
          counts[path] = count
        end
      end
    end
  end
end
