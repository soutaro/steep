# frozen_string_literal: true

require "yaml"

module Steep
  class Source
    # Injects convention annotations into module/concern sources at parse time,
    # driven by a sidecar (`sig/generated/.steep_module_self_types.yml`)
    # produced by a framework-aware generator (e.g. rbs_infer). Two kinds:
    #
    #   * `# @type self:` / `# @type instance:` placed inside a module body
    #     (the `anchor` / `annotations` entry keys); and
    #   * `# @implements <Module>` appended to a DSL block's opener line (the
    #     `blocks` entry key) — e.g. an `ActiveSupport::Concern`'s
    #     `class_methods do … end`, so Steep checks that block as an
    #     implementation of the given module (its `def`s attach there and
    #     `self` resolves there). It rides on the `do`/`{` line so no line is
    #     added and reported line numbers stay aligned with the real source.
    #
    # Steep is framework-agnostic here: it knows nothing about Rails, concerns,
    # or path conventions. It only looks up an entry by path and places the
    # given comment lines at the right AST scope. Deciding *what* to inject
    # (the module's real name, the including class, whether it's a concern, the
    # DSL call name and its target module) is the generator's job — it has the
    # AST and the framework conventions.
    #
    # Sidecar format (keyed by project-relative source path):
    #
    #   "app/models/search/record/sqlite.rb":
    #     anchor: "SQLite"
    #     annotations:
    #       - "# @type self: singleton(Search::Record) & singleton(Search::Record::SQLite)"
    #       - "# @type instance: Search::Record & Search::Record::SQLite"
    #   "app/models/post/taggable.rb":
    #     blocks:
    #       - call: "class_methods"
    #         implements: "::Post::Taggable::ClassMethods"
    #
    # `anchor` is the leaf constant name; it locates the target scope so a
    # comment for a nested module lands *inside* that module's body (a trailing
    # end-of-file comment would bind to the enclosing scope instead).
    #
    # Block injection relies on the upstream `@implements` annotation — legacy
    # (absent from the current `manual/annotations.md`, but still parsed and
    # handled: `TypeConstruction#for_block` reads it to rebind the block body's
    # module context and self type). No checker change is needed; this only
    # places the comment at the right offset.
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

        # Appends `# @implements <implements>` to the opener line of each
        # receiverless block call named `call`, for every `blocks` spec
        # (`{ "call" => ..., "implements" => ... }`). Lets Steep check a DSL
        # block — e.g. `class_methods do … end` — as an implementation of the
        # target module. The comment rides on the `do`/`{` line itself so it
        # adds NO line: Steep reports against the injected source, and every
        # line number stays aligned with the real file (the same
        # line-preservation guarantee `inject` keeps). Idempotent (skips a
        # block that already carries the annotation) and purely mechanical;
        # falls back to the original source on any parse error.
        def inject_blocks(source_code, blocks:)
          return source_code if blocks.empty?

          result = Prism.parse(source_code)
          return source_code unless result.success?

          insertions = blocks.flat_map do |spec|
            call_name = spec["call"].to_s
            module_name = spec["implements"].to_s
            next [] if call_name.empty? || module_name.empty?

            annotation = "# @implements #{module_name}"
            find_block_calls(result.value, call_name).filter_map do |call|
              block = call.block
              next unless block.is_a?(Prism::BlockNode) && block.opening_loc

              block_src = source_code.byteslice(block.location.start_offset, block.location.length) || ""
              next if block_src.include?(annotation)

              block_insertion(source_code, block, annotation)
            end
          end
          return source_code if insertions.empty?

          # Back to front so earlier byte offsets stay valid.
          insertions.sort_by { |i| -i[:offset] }.each_with_object(source_code.dup) do |i, out|
            out.replace(out.byteslice(0, i[:offset]) + i[:text] + out.byteslice(i[:offset]..))
          end
        rescue StandardError
          source_code
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

        # The `{ offset:, text: }` insertion that appends `annotation` to the
        # end of `block`'s opener line — after the block parameters (`do |x|`)
        # when present, else right after `do`/`{`. Returns nil (skips) when the
        # body shares that line (an inline `{ … }`), where a trailing `#`
        # comment would swallow the body; that shape never appears for the
        # concern DSL, so skipping is safer than corrupting the source.
        def block_insertion(source_code, block, annotation)
          open_end = block.parameters&.location&.end_offset || block.opening_loc.end_offset
          newline = source_code.byteindex("\n", open_end) || source_code.bytesize
          tail = source_code.byteslice(open_end, newline - open_end) || ""
          return nil unless tail.strip.empty?

          { offset: open_end, text: " #{annotation}" }
        end

        # Every receiverless call named `call_name` that carries a `do … end` /
        # `{ … }` block, anywhere in the tree.
        def find_block_calls(root, call_name)
          target = call_name.to_sym
          found = []
          walk = lambda do |node|
            return unless node.is_a?(Prism::Node)

            if node.is_a?(Prism::CallNode) && node.name == target &&
               node.receiver.nil? && node.block.is_a?(Prism::BlockNode)
              found << node
            end
            node.compact_child_nodes.each { |c| walk.call(c) }
          end
          walk.call(root)
          found
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
