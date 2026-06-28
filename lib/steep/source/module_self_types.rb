# frozen_string_literal: true

require "yaml"

module Steep
  class Source
    # Injects `# @type self:` / `# @type instance:` annotations into module/
    # concern sources at parse time, driven by a sidecar
    # (`sig/generated/.steep_module_self_types.yml`) produced by a
    # framework-aware generator (e.g. rbs_infer).
    #
    # Steep is framework-agnostic here: it knows nothing about Rails, concerns,
    # or path conventions. It only looks up an entry by path and places the
    # given comment lines at the right AST scope. Deciding *what* to inject
    # (the module's real name, the including class, whether it's a concern) is
    # the generator's job — it has the AST and the framework conventions.
    #
    # Sidecar format (keyed by project-relative source path):
    #
    #   "app/models/search/record/sqlite.rb":
    #     anchor: "SQLite"
    #     annotations:
    #       - "# @type self: singleton(Search::Record) & singleton(Search::Record::SQLite)"
    #       - "# @type instance: Search::Record & Search::Record::SQLite"
    #
    # `anchor` is the leaf constant name; it locates the target scope so a
    # comment for a nested module lands *inside* that module's body (a trailing
    # end-of-file comment would bind to the enclosing scope instead).
    module ModuleSelfTypes
      DEFAULT_SIDECAR_PATH = "sig/generated/.steep_module_self_types.yml"

      class << self
        # The sidecar entry for `path` (`{ "anchor" => ..., "annotations" =>
        # [...] }`), or nil. Keys are project-relative; an absolute path matches
        # by its tail.
        def entry_for(path)
          table = load_table
          return nil if table.empty?

          key = path.to_s
          table[key] || table[relative(key)] || table.find { |k, _| key.end_with?("/#{k}") }&.last
        end

        # Places `annotations` at the scope named `anchor`. A module nested in a
        # wrapper class/module gets the lines inserted inside its body; a
        # top-level / compact module gets them appended at end-of-file (which
        # preserves every original line number). Lines already present are
        # skipped, so it's idempotent. Purely mechanical — no framework
        # knowledge.
        def inject(source_code, annotations:, anchor:)
          missing = annotations.reject { |line| source_code.include?(line) }
          return source_code if missing.empty?

          node, nested = find_target_scope(source_code, anchor)
          if node && nested
            insert_in_body(source_code, node, missing)
          else
            append_at_end(source_code, missing)
          end
        rescue StandardError
          append_at_end(source_code, missing)
        end

        # Drops the memoized sidecar. The mtime check below makes this mostly
        # unnecessary, but rbs_infer can call it between stabilization passes
        # that rewrite the sidecar, mirroring its other Steep resets.
        def reset!
          @table = nil
          @table_key = nil
        end

        private

        # Memoized, invalidated by the sidecar's mtime so a regenerated sidecar
        # (between dependency levels) is picked up without an explicit reset.
        def load_table
          sidecar = Pathname(DEFAULT_SIDECAR_PATH)
          mtime = sidecar.file? ? sidecar.mtime : nil
          key = [sidecar.to_s, mtime]
          return @table if @table && @table_key == key

          @table_key = key
          @table = mtime ? parse(sidecar) : {}
        end

        def parse(sidecar)
          raw = YAML.safe_load(sidecar.read)
          raw.is_a?(Hash) ? raw : {}
        rescue Psych::Exception, SystemCallError => e
          Steep.logger.warn { "[module_self_types] failed to parse #{sidecar}: #{e.message}" } if defined?(Steep.logger)
          {}
        end

        def relative(path)
          prefix = "#{Dir.pwd}/"
          path.start_with?(prefix) ? path[prefix.length..] : path
        end

        # Returns [innermost ModuleNode/ClassNode named `anchor`, nested?] where
        # nested? is true when the node is enclosed in another class/module.
        def find_target_scope(source_code, anchor)
          result = Prism.parse(source_code)
          return [nil, false] unless result.success?

          found = nil
          found_nested = false
          best_depth = -1
          walk = lambda do |node, depth, enclosed|
            return unless node.is_a?(Prism::Node)

            is_scope = node.is_a?(Prism::ModuleNode) || node.is_a?(Prism::ClassNode)
            if is_scope
              cpath = node.constant_path
              name = cpath.respond_to?(:name) ? cpath.name.to_s : nil
              if name == anchor && depth > best_depth
                found = node
                found_nested = enclosed
                best_depth = depth
              end
            end

            child_enclosed = enclosed || is_scope
            node.compact_child_nodes.each { |c| walk.call(c, depth + 1, child_enclosed) }
          end
          walk.call(result.value, 0, false)
          [found, found_nested]
        end

        # Inserts the lines, indented one level past the declaration, right
        # before the node's closing `end`.
        def insert_in_body(source_code, node, annotation_lines)
          return append_at_end(source_code, annotation_lines) unless node.respond_to?(:end_keyword_loc) && node.end_keyword_loc

          indent = " " * (node.location.start_column + 2)
          block = annotation_lines.map { |line| "#{indent}#{line}\n" }.join
          end_offset = node.end_keyword_loc.start_offset
          line_start = (source_code.rindex("\n", end_offset) || -1) + 1
          source_code[0...line_start] + block + source_code[line_start..]
        end

        def append_at_end(source_code, annotation_lines)
          source_code.rstrip + "\n\n" + annotation_lines.join("\n") + "\n"
        end
      end
    end
  end
end
