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
        close_ivar_effects(merge(entries))
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

      # Closes `may_write_ivars` over the self-call graph (felixefelip/steep#68,
      # item 1): a method may write every ivar its callees may write.
      #
      #   redirect_to        writes @halted directly
      #   authenticate_user  calls redirect_to  => may write @halted
      #
      # Without the closure the caller of `authenticate_user` keeps a narrowing
      # of `@halted` that the callee already invalidated — the write is real,
      # just one frame down (and, in the Rails guard shape, two blocks deep as
      # well).
      #
      # Iterates to a fixpoint, so a chain of any depth converges; cycles are
      # handled by the fixpoint itself (the sets only grow, and are bounded by
      # the declared ivars).
      def close_ivar_effects(entries)
        by_key = entries.to_h { |entry| [entry_key(entry), entry] }
        effects = by_key.transform_values { |entry| entry.may_write_ivars.dup }

        loop do
          changed = false
          by_key.each do |key, entry|
            entry.self_call_deps.each do |dep|
              callee_effect = effects[dep] or next
              before = effects[key].size
              effects[key].merge(callee_effect)
              changed ||= effects[key].size != before
            end
          end
          break unless changed
        end

        resolved = by_key.transform_values do |entry|
          entry.with_may_write(effects[key_of(entry)])
        end

        # felixefelip/steep#68 item 2: resolve each conditional-return whose gate
        # is expressed `via` a self-method (`redirect_to`) to the ivar that
        # method actually writes, now that the may-write closure is known. A gate
        # that resolves to no ivar (the "halt" didn't write anything) is dropped.
        resolved.each_value do |entry|
          resolve_gates!(entry.conditional_returns, entry, effects)
          resolve_gates!(entry.conditional_const_returns, entry, effects)
        end

        resolved.values.reject(&:empty?)
      end

      # Resolve each spec whose gate is expressed `via` a self-method to the ivar
      # that method actually writes (via item 1's self-call edges, which carry
      # the declaring class so an inherited `redirect_to` resolves correctly),
      # then drop any spec left without a gate ivar.
      def resolve_gates!(specs, entry, effects)
        specs.each_value do |spec|
          next if spec[:gate_ivar]

          via = spec[:gate_via] or next
          dep = entry.self_call_deps.find { |d| d.end_with?("##{via}") }
          spec[:gate_ivar] = dep && effects[dep]&.first
        end
        specs.reject! { |_, spec| spec[:gate_ivar].nil? }
      end

      def key_of(entry)
        entry_key(entry)
      end

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
            callbacks: @project.callbacks,
            delegation_registry: @project.delegation_registry,
            constructor_bindings: @project.constructor_binding_registry,
            return_forwarding: @project.return_forwarding_registry,
            return_alias: @project.return_alias_registry
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
            merged_establishes = (existing.returns_establishes | entry.returns_establishes)
            by_key[key] = InferredEntry.new(
              class_name: existing.class_name,
              method_name: existing.method_name,
              singleton: existing.singleton,
              ivars: merged_ivars,
              self_type_string: existing.self_type_string || entry.self_type_string,
              when_true_ivars: existing.when_true_ivars,
              when_true_self_type_string: existing.when_true_self_type_string,
              returns_establishes: merged_establishes,
              may_write_ivars: existing.may_write_ivars | entry.may_write_ivars,
              self_call_deps: existing.self_call_deps | entry.self_call_deps,
              returns_ivar: existing.returns_ivar || entry.returns_ivar,
              conditional_returns: existing.conditional_returns.merge(entry.conditional_returns),
              conditional_const_returns: existing.conditional_const_returns.merge(entry.conditional_const_returns)
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
