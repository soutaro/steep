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
    #   * `# @implements <Module>` on a DSL block's opener line plus, per spec,
    #     `# @type self: <Type>` on each method-def line in that block (the
    #     `blocks` entry key) — e.g. an `ActiveSupport::Concern`'s
    #     `class_methods do … end`, so Steep checks the block as an
    #     implementation of <Module> (its `def`s attach there) whose method
    #     bodies run with <Type> as self (the including class's singleton, so
    #     the includer's scopes/class methods resolve). Both ride on existing
    #     lines, so no line is added and reported line numbers stay aligned
    #     with the real source.
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
    #         self: "singleton(::Post) & singleton(::Post::Taggable)"
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

        # Annotates each receiverless block call named `call`, for every
        # `blocks` spec (`{ "call" => ..., "implements" => ..., "self" => ...
        # }`): `# @implements <implements>` on the opener line, and — when
        # `self` is given — `# @type self: <self>` on each method-def line in
        # the block (see `block_annotation_insertions`). Lets Steep check a DSL
        # block — e.g. `class_methods do … end` — as an implementation of the
        # target module whose methods run with the includer's class self.
        # Every comment rides on an existing line, so it adds NO line: Steep
        # reports against the injected source, and every line number stays
        # aligned with the real file (the same line-preservation guarantee
        # `inject` keeps). Idempotent and purely mechanical; falls back to the
        # original source on any parse error.
        def inject_blocks(source_code, blocks:)
          return source_code if blocks.empty?

          result = Prism.parse(source_code)
          return source_code unless result.success?

          insertions = blocks.flat_map do |spec|
            call_name = spec["call"].to_s
            module_name = spec["implements"].to_s
            next [] if call_name.empty? || module_name.empty?

            implements = "# @implements #{module_name}"
            self_type = spec["self"].to_s
            self_annotation = self_type.empty? ? nil : "# @type self: #{self_type}"

            find_block_calls(result.value, call_name).flat_map do |call|
              block = call.block
              next [] unless block.is_a?(Prism::BlockNode) && block.opening_loc

              block_annotation_insertions(source_code, block, implements, self_annotation)
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

        # All `{ offset:, text: }` insertions for one annotated DSL block:
        #   * `# @implements <module>` on the block opener line; and
        #   * `# @type self: <type>` on each direct method-def line inside the
        #     block (only when a self type is given).
        # The opener `@implements` makes the block's `def`s attach to <module>;
        # the per-def `@type self:` widens each method body's self to the
        # including class's singleton so the includer's scopes/class methods
        # resolve there (a block-level self annotation does NOT reach into a
        # method body — its self comes from the method's owner). Every
        # annotation rides on an existing line, so nothing shifts; an
        # annotation that cannot ride its line (inline body, or already
        # present) is skipped — making this idempotent.
        def block_annotation_insertions(source_code, block, implements, self_annotation)
          insertions = []

          open_end = block.parameters&.location&.end_offset || block.opening_loc.end_offset
          insertions << append_to_line(source_code, open_end, implements)

          if self_annotation
            each_block_def(block) do |defn|
              insertions << append_to_line(source_code, def_signature_end(defn), self_annotation)
            end
          end

          insertions.compact
        end

        # A `{ offset:, text: }` that appends `annotation` to the source line
        # holding `offset`, when nothing but whitespace follows `offset` on that
        # line — so the comment adds no line and shifts nothing. Returns nil
        # when the rest of the line is non-blank (an inline body, or an
        # annotation already there), where a trailing `#` would swallow it.
        def append_to_line(source_code, offset, annotation)
          newline = source_code.byteindex("\n", offset) || source_code.bytesize
          tail = source_code.byteslice(offset, newline - offset) || ""
          return nil unless tail.strip.empty?

          { offset: offset, text: " #{annotation}" }
        end

        # The byte offset just past a def's signature — after the parameters
        # (`def foo(x)` / `def foo x`), else after the method name (`def foo`) —
        # where a trailing annotation can ride.
        def def_signature_end(node)
          node.rparen_loc&.end_offset || node.parameters&.location&.end_offset || node.name_loc.end_offset
        end

        # Yields each method definition that is a direct statement of `block`'s
        # body (the methods the `class_methods do` DSL contributes); nested
        # defs/classes have their own context and are left alone.
        def each_block_def(block)
          body = block.body
          return unless body.is_a?(Prism::StatementsNode)

          body.body.each do |stmt|
            yield stmt if stmt.is_a?(Prism::DefNode)
          end
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
