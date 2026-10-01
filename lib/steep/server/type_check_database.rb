module Steep
  module Server
    class TypeCheckDatabase
      Entry =
        _ = Struct.new(:name, :role, :start_line, :start_character, :end_line, :end_character, :kind, keyword_init: true) do
          # @implements Entry

          def code
            code = ROLE_CODES.fetch(role)
            if kind = self.kind
              code |= KIND_CODES.fetch(kind) << 1
            end
            code
          end

          def to_wire
            [name, code, start_line, start_character, end_line, end_character]
          end

          def self.from_wire(array)
            code = array[1] #: Integer
            Entry.new(
              name: array[0],
              role: ROLES.fetch(code & 1),
              kind: KINDS.fetch(code >> 1, nil),
              start_line: array[2],
              start_character: array[3],
              end_line: array[4],
              end_character: array[5]
            )
          end
        end

      Definition = _ = Struct.new(:name, :kind, :location, keyword_init: true)

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

        def each(&block)
          @names.each(&block)
        end
      end

      FileResult = _ = Struct.new(:target, :diagnostics, :entries, :stats, keyword_init: true)

      ROLE_CODES = { definition: 0, reference: 1 } #: Hash[Entry::role, Integer]
      ROLES = ROLE_CODES.invert #: Hash[Integer, Entry::role]

      KIND_CODES = { class: 1, module: 2, interface: 3, type_alias: 4, constant: 5, global: 6, method: 7, attribute: 8 } #: Hash[Entry::kind, Integer]
      KINDS = KIND_CODES.invert #: Hash[Integer, Entry::kind]

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

      def self.rbs_entries_by_path(env)
        RBSEntryBuilder.new.env(env).entries
      end

      attr_reader :pool

      def initialize
        @sources = {}
        @signatures = {}
        @rbs = {}
        @pool = NamePool.new
        @source_paths = {}
        @rbs_paths = {}
      end

      def update_source(path:, target:, diagnostics:, entries:, stats: nil)
        @sources[path] = replace_result(
          @sources.fetch(path, nil),
          @source_paths,
          path: path,
          target: target,
          diagnostics: diagnostics,
          entries: entries,
          stats: stats
        )
      end

      def update_signature(path:, target:, diagnostics:)
        targets = (@signatures[path] ||= {})
        targets[target] = diagnostics || targets.fetch(target, nil) || []
      end

      def update_rbs(path:, target:, entries:)
        return unless entries

        targets = (@rbs[path] ||= {})
        if old = targets[target]
          release_entries(@rbs_paths, path, old)
        end

        targets[target] = pack_entries(@rbs_paths, path, entries)
      end

      def remove(path)
        if result = @sources.delete(path)
          release_entries(@source_paths, path, result.entries)
        end

        @signatures.delete(path)

        if targets = @rbs.delete(path)
          targets.each_value do |packed|
            release_entries(@rbs_paths, path, packed)
          end
        end
      end

      def checked?(path)
        @sources.key?(path) || @signatures.key?(path)
      end

      def paths
        @sources.keys | @signatures.keys
      end

      def each_source(&block)
        if block
          @sources.each do |path, result|
            yield path, result
          end
        else
          enum_for :each_source
        end
      end

      def diagnostics(path)
        merged = [] #: Array[untyped]

        if result = @sources.fetch(path, nil)
          merged.concat(result.diagnostics)
        end

        if targets = @signatures.fetch(path, nil)
          targets.each_value do |diagnostics|
            merged.concat(diagnostics)
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

      def matching_names(query)
        query = query.upcase

        names = [] #: Array[String]
        pool.each do |_, name|
          names << name if query.empty? || name.upcase.include?(query)
        end
        names
      end

      def rbs_definitions(names)
        ids = {} #: Hash[Integer, String]
        names.each do |name|
          if id = pool.id_of(name)
            ids[id] = name
          end
        end

        # Each file is read once for all of the names
        paths = ids.each_key.flat_map { @rbs_paths.fetch(_1, nil)&.keys || [] }.uniq

        definitions = [] #: Array[Definition]

        paths.each do |path|
          # The library RBS files have the same entries in every target, which are read once
          arrays = @rbs.fetch(path).values.uniq
          seen = arrays.size > 1 ? Set[] : nil #: Set[Array[Integer]]?

          arrays.each do |packed|
            index = 0
            while index < packed.size
              id = packed.fetch(index)
              code = packed.fetch(index + 1)

              if code & 1 == ROLE_CODES.fetch(:definition) && (kind = KINDS.fetch(code >> 1, nil))
                name = ids.fetch(id, nil)

                if name && (!seen || seen.add?(packed[index, ENTRY_SIZE] || raise))
                  definitions << Definition.new(
                    name: name,
                    kind: kind,
                    location: Location.new(
                      path: path,
                      source: :rbs,
                      start_line: packed.fetch(index + 2),
                      start_character: packed.fetch(index + 3),
                      end_line: packed.fetch(index + 4),
                      end_character: packed.fetch(index + 5)
                    )
                  )
                end
              end

              index += ENTRY_SIZE
            end
          end
        end

        definitions
      end

      def entry_count
        count = 0

        @sources.each_value do |result|
          count += result.entries.size / ENTRY_SIZE
        end

        @rbs.each_value do |targets|
          targets.each_value do |packed|
            count += packed.size / ENTRY_SIZE
          end
        end

        count
      end

      private

      def replace_result(old, name_paths, path:, target:, diagnostics:, entries:, stats:)
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
          entries: packed,
          stats: diagnostics ? stats : old&.stats
        )
      end

      def pack_entries(name_paths, path, entries)
        packed = [] #: Array[Integer]

        entries.each do |entry|
          id = pool.intern(entry.name)
          track_name(name_paths, id, path)
          packed << id << entry.code << entry.start_line << entry.start_character << entry.end_line << entry.end_character
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

        if paths = @rbs_paths.fetch(id, nil)
          paths.each_key do |path|
            @rbs.fetch(path).each_value do |packed|
              collect_locations(locations, packed, id, role_code, path: path, source: :rbs)
            end
          end
        end

        locations.uniq!
        locations
      end

      def collect_locations(locations, array, id, role_code, path:, source:)
        index = 0
        while index < array.size
          if array.fetch(index) == id && array.fetch(index + 1) & 1 == role_code
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
