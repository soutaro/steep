# frozen_string_literal: true

module Steep
  class Source
    # Appends `# @type self:` / `# @type instance:` annotations to module and
    # concern files at parse time, without touching files on disk.
    #
    # Mirrors the ErbSelfTypeResolver pattern: annotations are appended at the
    # END of the source (after the closing `end`), so original line numbers are
    # preserved and IDE error messages point to the correct lines.
    #
    # Rules:
    #   - ActiveSupport::Concern modules get both annotations appended:
    #       # @type self: singleton(Post) & singleton(Post::Notifiable)
    #       # @type instance: Post & Post::Notifiable
    #
    #   - Plain modules get only the instance annotation appended:
    #       # @type instance: Post & Post::Taggable
    #
    # Including class is resolved from the module's namespace:
    #   Post::Notifiable  → Post
    #   User::Recoverable → User
    #
    # For helpers and controller concerns the including class is always
    # ApplicationController (derived by Rails convention, not namespace).
    #
    # Idempotent: skips files that already contain the annotation for the module.
    module ModuleSelfTypeResolver
      MODELS_PREFIX = "app/models/"
      HELPERS_PREFIX = "app/helpers/"
      CONTROLLER_CONCERNS_PREFIX = "app/controllers/concerns/"

      class << self
        # Returns the annotated source_code, or the original if nothing to inject.
        def annotate(path, source_code)
          path_str = path.to_s
          return source_code unless path_str.end_with?(".rb")

          helpers_idx = path_str.index(HELPERS_PREFIX)
          return annotate_helper(path_str, source_code, helpers_idx) if helpers_idx

          controller_concerns_idx = path_str.index(CONTROLLER_CONCERNS_PREFIX)
          return annotate_controller_concern(path_str, source_code, controller_concerns_idx) if controller_concerns_idx

          idx = path_str.index(MODELS_PREFIX)
          return source_code unless idx

          relative = path_str[(idx + MODELS_PREFIX.length)..].delete_suffix(".rb")
          # Rails treats app/models/concerns/ as an autoload root (no namespace)
          relative = relative.delete_prefix("concerns/")
          module_name = relative.split("/").map { |s| camelize(s) }.join("::")
          return source_code if module_name.empty?

          parts = module_name.split("::")
          return source_code if parts.size < 2

          including_class = parts[0..-2].join("::")

          is_concern = source_code.include?("extend ActiveSupport::Concern")

          # Idempotency
          return source_code if source_code.match?(/@type (?:self|instance):.*#{Regexp.escape(module_name)}/)

          if is_concern
            append_concern_annotations(source_code, module_name, including_class)
          else
            append_module_annotation(source_code, module_name, including_class)
          end
        end

        private

        def annotate_controller_concern(path_str, source_code, idx)
          relative = path_str[(idx + CONTROLLER_CONCERNS_PREFIX.length)..].delete_suffix(".rb")
          module_name = relative.split("/").map { |s| camelize(s) }.join("::")
          return source_code if module_name.empty?

          including_class = "ApplicationController"

          # Idempotency
          return source_code if source_code.match?(/@type instance:.*#{Regexp.escape(module_name)}/)

          is_concern = source_code.include?("extend ActiveSupport::Concern")

          if is_concern
            append_concern_annotations(source_code, module_name, including_class)
          else
            append_module_annotation(source_code, module_name, including_class)
          end
        end

        def annotate_helper(path_str, source_code, idx)
          relative = path_str[(idx + HELPERS_PREFIX.length)..].delete_suffix(".rb")
          module_name = relative.split("/").map { |s| camelize(s) }.join("::")
          return source_code if module_name.empty?

          including_class = "ApplicationController"

          # Idempotency
          return source_code if source_code.match?(/@type instance:.*#{Regexp.escape(module_name)}/)

          is_concern = source_code.include?("extend ActiveSupport::Concern")

          if is_concern
            append_concern_annotations(source_code, module_name, including_class)
          else
            append_module_annotation(source_code, module_name, including_class)
          end
        end

        # Both @type self: and @type instance: for a concern.
        def append_concern_annotations(source_code, module_name, including_class)
          self_annotation     = "# @type self: singleton(#{including_class}) & singleton(#{module_name})"
          instance_annotation = "# @type instance: #{including_class} & #{module_name}"
          inject(source_code, module_name, [self_annotation, instance_annotation])
        end

        # @type instance: for a plain module.
        def append_module_annotation(source_code, module_name, including_class)
          annotation = "# @type instance: #{including_class} & #{module_name}"
          inject(source_code, module_name, [annotation])
        end

        # Places the annotation so Steep associates it with the target module's
        # body.
        #
        # For a top-level / compact module (`module Post::Notifiable`) a trailing
        # comment at end-of-file attaches to the module, so we append there —
        # this preserves every original line number (mirrors the ERB convention).
        #
        # For a module nested inside a class/module wrapper (e.g.
        # `class User; module Idade; ...; end; end`) the end-of-file comment
        # attaches to the OUTER scope and Steep ignores it for the inner module —
        # `self` then falls back to `Object & User::Idade` and calls to the
        # including class (`data_nascimento`) don't resolve. So we insert the
        # annotation as the last line *inside* the innermost module body instead;
        # only the closing `end`s shift, method line numbers stay put.
        #
        # Falls back to appending at end-of-file on any parse/locate failure.
        def inject(source_code, module_name, annotation_lines)
          last_segment = module_name.split("::").last
          node, nested = find_target_scope(source_code, last_segment)

          if node && nested
            insert_in_body(source_code, node, annotation_lines)
          else
            append_at_end(source_code, annotation_lines)
          end
        rescue StandardError
          append_at_end(source_code, annotation_lines)
        end

        def append_at_end(source_code, annotation_lines)
          source_code.rstrip + "\n\n" + annotation_lines.join("\n") + "\n"
        end

        # Returns [innermost matching ModuleNode/ClassNode, nested?] where
        # nested? is true when the node is enclosed in another class/module.
        def find_target_scope(source_code, last_segment)
          return [nil, false] unless defined?(Prism)

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
              if name == last_segment && depth > best_depth
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

        # Inserts the annotation lines, indented one level past the declaration,
        # immediately before the node's closing `end` keyword.
        def insert_in_body(source_code, node, annotation_lines)
          return append_at_end(source_code, annotation_lines) unless node.respond_to?(:end_keyword_loc) && node.end_keyword_loc

          indent = " " * (node.location.start_column + 2)
          block = annotation_lines.map { |line| "#{indent}#{line}\n" }.join
          end_offset = node.end_keyword_loc.start_offset
          line_start = (source_code.rindex("\n", end_offset) || -1) + 1
          source_code[0...line_start] + block + source_code[line_start..]
        end

        def camelize(str)
          str.split(/[_-]/).map(&:capitalize).join
        end
      end
    end
  end
end
