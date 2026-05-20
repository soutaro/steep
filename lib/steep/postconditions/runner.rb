module Steep
  module Postconditions
    # Drives postcondition inference across all source files in a project.
    # Modeled after `Steep::Contracts::Runner` (preconditions side).
    #
    # Flow per target:
    #
    #   1. Load the target's RBS signatures into a fresh `SignatureService`.
    #   2. For each Ruby source file in the target's `source_pattern`,
    #      parse + type-check with the *already-loaded* postconditions in
    #      scope (so previously-inferred entries inform later inference —
    #      e.g. a call site that consumes a refined ivar gets the right
    #      type).
    #   3. Run `Inferrer.infer` on the typed result, accumulating
    #      `InferredEntry` values.
    #
    # Across targets, entries with the same `(class, method)` are merged
    # by union of `ivars` (entries that disagree on a key keep the first
    # one wins, with a warning — defensive default).
    class Runner
      DEFAULT_OUTPUT_PATH = Pathname("sig/generated/.steep_postconditions.yml").freeze

      def self.run(project)
        new(project).run
      end

      def initialize(project)
        @project = project
      end

      def run
        entries = []
        @project.targets.each do |target|
          entries.concat(infer_for_target(target))
        end
        merge(entries)
      end

      def output_path
        @project.absolute_path(DEFAULT_OUTPUT_PATH)
      end

      def write(entries)
        if entries.empty?
          output_path.delete if output_path.file?
        else
          Writer.write(output_path, entries)
        end
      end

      private

      def infer_for_target(target)
        loader = Project::Target.construct_env_loader(options: target.options, project: @project)
        file_loader = Services::FileLoader.new(base_dir: @project.base_dir)

        file_loader.each_path_in_patterns(target.signature_pattern) do |path|
          absolute = @project.absolute_path(path)
          loader.add(path: absolute) if absolute.file?
        end

        signature_service = Services::SignatureService.load_from(loader, implicitly_returns_nil: target.implicitly_returns_nil)
        status = signature_service.status
        return [] unless status.is_a?(Services::SignatureService::LoadedStatus)

        subtyping = status.subtyping
        resolver = status.constant_resolver
        out = []

        file_loader.each_path_in_patterns(target.source_pattern) do |path|
          absolute = @project.absolute_path(path)
          next unless absolute.file? && absolute.extname == ".rb"

          text = absolute.read
          source = begin
                     Source.parse(text, path: absolute, factory: subtyping.factory)
                   rescue ::Parser::SyntaxError, AnnotationParser::SyntaxError
                     next
                   end

          # Use the project's loaded postconditions so a method that
          # consumes an ivar refined by an earlier-discovered postcondition
          # types correctly — without this, an inference pass could
          # spuriously report "method on Union does not exist" inside the
          # body, and downstream code would see the call as Type::Error,
          # masking real refinements.
          typing = Services::TypeCheckService.type_check(
            source: source,
            subtyping: subtyping,
            constant_resolver: resolver,
            cursor: nil,
            contracts: @project.contracts,
            postconditions: @project.postconditions,
            callbacks: @project.callbacks
          )

          out.concat(Inferrer.infer(source, typing, subtyping))
        end

        out
      end

      def merge(entries)
        by_key = {}
        entries.each do |entry|
          key = entry_key(entry)
          if (existing = by_key[key])
            merged_ivars = existing.ivars.dup
            entry.ivars.each do |name, type|
              if merged_ivars.key?(name) && merged_ivars[name] != type
                Steep.logger.warn { "[postconditions] inferred conflicting types for #{key} #{name}: #{merged_ivars[name]} vs #{type}; keeping first" }
                next
              end
              merged_ivars[name] = type
            end
            by_key[key] = InferredEntry.new(
              class_name: existing.class_name,
              method_name: existing.method_name,
              singleton: existing.singleton,
              ivars: merged_ivars
            )
          else
            by_key[key] = entry
          end
        end
        by_key.values
      end

      def entry_key(entry)
        sep = entry.singleton ? "." : "#"
        "#{entry.class_name}#{sep}#{entry.method_name}"
      end
    end
  end
end
