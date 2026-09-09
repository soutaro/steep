module Steep
  module Server
    class TypeCheckDatabase
      Entry =
        _ = Struct.new(:name, :role, :start_line, :start_character, :end_line, :end_character, keyword_init: true) do
          # @implements Entry

          def to_wire
            [name, ROLE_CODES.fetch(role), start_line, start_character, end_line, end_character]
          end

          def self.from_wire(array)
            Entry.new(
              name: array[0],
              role: ROLES.fetch(array[1]),
              start_line: array[2],
              start_character: array[3],
              end_line: array[4],
              end_character: array[5]
            )
          end
        end

      Location =
        _ = Struct.new(:path, :source, :start_line, :start_character, :end_line, :end_character, keyword_init: true) do
          # @implements Location

          def lsp_range
            {
              start: { line: start_line, character: start_character },
              end: { line: end_line, character: end_character }
            }
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

      FileResult = _ = Struct.new(:target, :diagnostics, :entries, keyword_init: true)

      ROLE_CODES = { definition: 0, reference: 1 } #: Hash[Entry::role, Integer]
      ROLES = ROLE_CODES.invert #: Hash[Integer, Entry::role]

      ENTRY_SIZE = 6

      def self.entries_from(typing)
        entries = [] #: Array[Entry]
        seen = Set[] #: Set[Array[untyped]]

        index = typing.source_index

        index.constant_index.each do |name, entry|
          entry.definitions.each do |node|
            if location = constant_definition_location(node)
              push_entry(entries, seen, name: name.to_s, role: :definition, location: location)
            end
          end
          entry.references.each do |node|
            push_entry(entries, seen, name: name.to_s, role: :reference, location: node.location.expression)
          end
        end

        index.method_index.each do |name, entry|
          entry.definitions.each do |node|
            location = (_ = node.location).name #: Parser::Source::Range
            push_entry(entries, seen, name: name.to_s, role: :definition, location: location)
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
            push_entry(entries, seen, name: decl.method_name.to_s, role: :reference, location: location)
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

      def self.push_entry(entries, seen, name:, role:, location:)
        key = [name, role, location.line, location.column, location.last_line, location.last_column] #: Array[untyped]
        return if seen.include?(key)
        seen << key

        entries << Entry.new(
          name: name,
          role: role,
          start_line: location.line - 1,
          start_character: location.column,
          end_line: location.last_line - 1,
          end_character: location.last_column
        )
      end

      def self.rbs_entries_by_path(index)
        entries = {} #: Hash[Pathname, Array[Entry]]
        paths = {} #: Hash[String, Pathname]

        index.type_index.each do |type_name, entry|
          entry.declarations.each do |decl|
            location = rbs_declaration_location(decl) or next
            push_rbs_entry(entries, paths, name: type_name.to_s, location: location)
          end
        end

        index.method_index.each do |method_name, entry|
          entry.declarations.each do |decl|
            location = rbs_declaration_location(decl) or next
            push_rbs_entry(entries, paths, name: method_name.to_s, location: location)
          end
        end

        index.const_index.each do |const_name, entry|
          entry.declarations.each do |decl|
            location = rbs_declaration_location(decl) or next
            push_rbs_entry(entries, paths, name: const_name.to_s, location: location)
          end
        end

        index.global_index.each do |global_name, entry|
          entry.declarations.each do |decl|
            location = rbs_declaration_location(decl) or next
            push_rbs_entry(entries, paths, name: global_name.to_s, location: location)
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

      def self.push_rbs_entry(entries, paths, name:, location:)
        buffer_name = location.buffer.name.to_s
        path = (paths[buffer_name] ||= Pathname(buffer_name))

        (entries[path] ||= []) << Entry.new(
          name: name,
          role: :definition,
          start_line: location.start_line - 1,
          start_character: location.start_column,
          end_line: location.end_line - 1,
          end_character: location.end_column
        )
      end

      attr_reader :pool

      def initialize
        @sources = {}
        @signatures = {}
        @pool = NamePool.new
        @source_paths = {}
        @signature_paths = {}
      end

      def update_source(path:, target:, diagnostics:, entries:)
        @sources[path] = replace_result(
          @sources.fetch(path, nil),
          @source_paths,
          path: path,
          target: target,
          diagnostics: diagnostics,
          entries: entries
        )
      end

      def update_signature(path:, target:, diagnostics:, entries:)
        targets = (@signatures[path] ||= {})
        targets[target] = replace_result(
          targets.fetch(target, nil),
          @signature_paths,
          path: path,
          target: target,
          diagnostics: diagnostics,
          entries: entries
        )
      end

      def remove(path)
        if result = @sources.delete(path)
          release_entries(@source_paths, path, result.entries)
        end

        if targets = @signatures.delete(path)
          targets.each_value do |result|
            release_entries(@signature_paths, path, result.entries)
          end
        end
      end

      def diagnostics(path)
        merged = [] #: Array[untyped]

        if result = @sources.fetch(path, nil)
          merged.concat(result.diagnostics)
        end

        if targets = @signatures.fetch(path, nil)
          targets.each_value do |result|
            merged.concat(result.diagnostics)
          end
        end

        merged.uniq!
        merged
      end

      def definitions(name)
        matching_locations(name, role: :definition)
      end

      def references(name)
        matching_locations(name, role: :reference)
      end

      def entry_count
        count = 0

        @sources.each_value do |result|
          count += result.entries.size / ENTRY_SIZE
        end

        @signatures.each_value do |targets|
          targets.each_value do |result|
            count += result.entries.size / ENTRY_SIZE
          end
        end

        count
      end

      private

      def replace_result(old, name_paths, path:, target:, diagnostics:, entries:)
        packed =
          if entries
            release_entries(name_paths, path, old.entries) if old
            pack_entries(name_paths, path, entries)
          elsif old
            old.entries
          else
            [] #: Array[Integer]
          end

        FileResult.new(
          target: target,
          diagnostics: diagnostics || old&.diagnostics || [],
          entries: packed
        )
      end

      def pack_entries(name_paths, path, entries)
        packed = [] #: Array[Integer]

        entries.each do |entry|
          id = pool.intern(entry.name)
          track_name(name_paths, id, path)
          packed << id << ROLE_CODES.fetch(entry.role) << entry.start_line << entry.start_character << entry.end_line << entry.end_character
        end

        packed
      end

      def matching_locations(name, role:)
        id = pool.id_of(name) or return []
        role_code = ROLE_CODES.fetch(role)

        locations = [] #: Array[Location]

        if paths = @source_paths.fetch(id, nil)
          paths.each_key do |path|
            collect_locations(locations, @sources.fetch(path).entries, id, role_code, path: path, source: :ruby)
          end
        end

        if paths = @signature_paths.fetch(id, nil)
          paths.each_key do |path|
            @signatures.fetch(path).each_value do |result|
              collect_locations(locations, result.entries, id, role_code, path: path, source: :rbs)
            end
          end
        end

        locations.uniq!
        locations
      end

      def collect_locations(locations, array, id, role_code, path:, source:)
        index = 0
        while index < array.size
          if array.fetch(index) == id && array.fetch(index + 1) == role_code
            locations << Location.new(
              path: path,
              source: source,
              start_line: array.fetch(index + 2),
              start_character: array.fetch(index + 3),
              end_line: array.fetch(index + 4),
              end_character: array.fetch(index + 5)
            )
          end
          index += ENTRY_SIZE
        end
      end

      def release_entries(name_paths, path, array)
        index = 0
        while index < array.size
          id = array.fetch(index)
          untrack_name(name_paths, id, path)
          pool.release(id)
          index += ENTRY_SIZE
        end
      end

      def track_name(name_paths, id, path)
        counts = (name_paths[id] ||= {})
        counts[path] = counts.fetch(path, 0) + 1
      end

      def untrack_name(name_paths, id, path)
        counts = name_paths.fetch(id)
        count = counts.fetch(path) - 1
        if count.zero?
          counts.delete(path)
          name_paths.delete(id) if counts.empty?
        else
          counts[path] = count
        end
      end
    end
  end
end
