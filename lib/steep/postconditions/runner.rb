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
        @sequences = [] #: Array[MethodEntryInferrer::RunnerSequence]
        @defined_method_keys = Set.new #: Set[String]
        @project.targets.each do |target|
          target_entries, target_sequences = infer_for_target(target)
          entries.concat(target_entries)
          @sequences.concat(target_sequences)
        end
        resolved = close_ivar_effects(merge(entries))
        @method_entry_facts = infer_method_entry_facts(resolved, @sequences)
        resolved
      end

      # felixefelip/steep#68 item 4: { "Class#method" => { self_methods:, consts: } }
      # — the facts proven at each method's entry by the guards that the runner
      # shows run before it. Nil until `run`.
      attr_reader :method_entry_facts

      def output_path
        @project.absolute_path(DEFAULT_OUTPUT_PATH)
      end

      def write(entries)
        facts = @method_entry_facts || {}
        if entries.empty? && facts.empty?
          output_path.delete if output_path.file?
        else
          Writer.write(output_path, entries, method_entry_facts: facts)
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

        # felixefelip/steep#68 item 5: a `Const.user = <non-nil>` write also
        # proves the OTHER constant attributes the setter establishes (its
        # override does `self.author_name = value&.full_name`). Expand each
        # guard's const-returns with those, when the singleton setter is
        # confirmed to delegate to the instance one.
        resolved.each_value { |entry| expand_transitive_const_returns(entry, resolved) }

        # felixefelip/rbs_infer#71 (piece 1): gate the UNCONDITIONAL establishment
        # (`Const.attr =` proves a sibling non-nil for the rest of the frame) on a
        # confirmed delegation. An instance setter's `establishes_consts` fires at
        # a `Const.attr =` write only when the singleton `Const.attr=` forwards to
        # it — otherwise the singleton could do anything and the establishment is
        # unsound. Drop the establishments where no delegating singleton exists so
        # the Writer serializes them only for the memoized-singleton shape.
        gate_establishes_consts_on_delegation!(resolved)

        resolved.values.reject(&:empty?)
      end

      # For each instance setter carrying `establishes_consts`, keep them only if
      # the sibling singleton setter (`Const.attr=`) is confirmed to delegate to
      # it; otherwise clear them. Runs before the `empty?` reject, so an instance
      # setter left with nothing to say is then dropped.
      def gate_establishes_consts_on_delegation!(resolved)
        resolved.each do |key, entry|
          next if entry.singleton || entry.establishes_consts.empty?

          method = entry.method_name.to_s
          next unless method.end_with?("=")

          singleton = resolved["#{entry.class_name}.#{method}"]
          next if singleton&.delegates_to_instance

          resolved[key] = entry.with_establishes_consts({})
        end
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

      # For each proven `Const.attr`, if the singleton `Const.attr=` delegates to
      # the instance setter and that setter establishes further attributes, add
      # `Const.<other>` under the same gate. `by_key` holds the setter entries.
      def expand_transitive_const_returns(entry, by_key)
        entry.conditional_const_returns.dup.each do |path, spec|
          const_name, attr = path.split(".", 2)
          next unless const_name && attr

          singleton = by_key["#{const_name}.#{attr}="]
          next unless singleton&.delegates_to_instance

          instance_setter = by_key["#{const_name}##{attr}="]
          next unless instance_setter

          instance_setter.establishes_consts.each do |other, type|
            other_path = "#{const_name}.#{other}"
            next if entry.conditional_const_returns.key?(other_path)

            entry.conditional_const_returns[other_path] = { gate_ivar: spec[:gate_ivar], type: type }
          end
        end
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
        sequences = [] #: Array[MethodEntryInferrer::RunnerSequence]

        file_loader.each_path_in_patterns(target.source_pattern) do |path|
          absolute = @project.absolute_path(path)
          # `.erb` too: a template checked with `@type self_method: X#m` (ERB
          # convention) is the source body of `X#m`, so it must contribute
          # `X#m` to `defined_method_keys` — otherwise the fact a guarded action
          # records for the view's entry is dropped by the defined-key filter.
          next unless absolute.file? && [".rb", ".erb"].include?(absolute.extname)

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
          sequences.concat(MethodEntryInferrer.sequences(source, typing))
          @defined_method_keys.merge(MethodEntryInferrer.defined_method_keys(source))
        end

        [out, sequences]
      end

      # felixefelip/steep#68 item 4. Turns each runner sequence into the facts
      # holding at each called method's entry: walk the calls in order, carrying
      # the union of every preceding guard's proven facts (a guard M running
      # after G runs only if G didn't halt, so G's facts hold unconditionally at
      # M's entry). A method appearing in more than one runner keeps the
      # INTERSECTION — a fact only holds at entry if every path there proves it.
      def infer_method_entry_facts(resolved, sequences)
        by_key = resolved.to_h { |e| [entry_key(e), e] }
        per_method = {} #: Hash[String, Hash[Symbol, Hash[untyped, String]]]
        seen = {} #: Hash[String, bool]

        sequences.each do |sequence|
          accumulated = { self_methods: {}, consts: {} } #: Hash[Symbol, Hash[untyped, String]]
          pending_guards = [] #: Array[[untyped, bool]]

          sequence.events.each do |event|
            case event[:kind]
            when :call
              key = "#{event[:class_name]}##{event[:method_name]}"
              entry = by_key[key]
              # A transparent halt-ivar getter (`def performed?; @halted; end`, `returns_ivar`)
              # is a predicate, not a fact-producing handler — the tool-neutral replacement for
              # the old `HALT_CHECK = :performed?` name-match (felixefelip/steep#78).
              next if halt_predicate?(entry)
              record_entry_facts(per_method, seen, key, accumulated, same_self: event[:same_self])
              # A call's guard facts (`conditional_*`) are proven only on its NON-halting exit,
              # so they hold downstream only once a halt check has ruled out the halting exit.
              # Hold them until a `:halt` promotes them.
              pending_guards << [entry, event[:same_self]] if entry
            when :halt
              # Past the halt, the pending calls did NOT halt — promote their conditional facts.
              pending_guards.each { |entry, same_self| accumulate_guard_facts(accumulated, entry, same_self: same_self) }
              pending_guards.clear
            when :const_write
              apply_const_write_facts(accumulated, by_key, event)
            end
          end
        end

        # Keep only facts for methods whose bodies are re-type-checked from source (the only
        # ones a fact can narrow). Drops the dead facts a chain walk records for builtin/stdlib
        # calls (`String#upcase`, `Class#new`).
        per_method.select! { |key, _| @defined_method_keys.include?(key) }
        per_method.reject { |_, facts| facts[:self_methods].empty? && facts[:consts].empty? }
      end

      # A method that transparently returns an ivar is a predicate (a halt check like
      # `performed?`), not a handler whose entry we track.
      def halt_predicate?(entry)
        entry ? !entry.returns_ivar.nil? : false
      end

      # Merge `accumulated` into `key`'s entry facts — intersecting with any
      # facts already recorded for `key` (from another sequence), since a fact
      # must hold on every path to be sound at entry. A cross-object call
      # (`same_self: false`) carries only const (global) facts — the caller's
      # `self`-method facts are about a different receiver.
      def record_entry_facts(per_method, seen, key, accumulated, same_self: true)
        self_methods = same_self ? accumulated[:self_methods] : {}
        snapshot = { self_methods: self_methods.dup, consts: accumulated[:consts].dup }
        if seen[key]
          existing = per_method[key]
          existing[:self_methods] = intersect(existing[:self_methods], snapshot[:self_methods])
          existing[:consts] = intersect(existing[:consts], snapshot[:consts])
        else
          per_method[key] = snapshot
          seen[key] = true
        end
      end

      def accumulate_guard_facts(accumulated, entry, same_self: true)
        return unless entry

        if same_self
          entry.conditional_returns.each do |method, spec|
            accumulated[:self_methods][method] = spec.fetch(:type).to_s
          end
        end
        entry.conditional_const_returns.each do |path, spec|
          accumulated[:consts][path] = spec.fetch(:type).to_s
        end
      end

      # A `Const.attr = <rhs>` in the flow establishes (non-nil rhs) or invalidates (nilable
      # rhs) every const the setter's `establishes_consts` proves — the sequence-level analogue
      # of `TypeConstruction#apply_const_establishes_on_write` (felixefelip/steep#78). The setter
      # entry is keyed the same whether instance (`#`) or singleton (`.`).
      def apply_const_write_facts(accumulated, by_key, event)
        base = event[:base]
        setter = by_key["#{base}##{event[:attr]}="] || by_key["#{base}.#{event[:attr]}="]
        return unless setter

        setter.establishes_consts.each do |other, type|
          path = "#{base}.#{other}"
          if event[:nonnil]
            accumulated[:consts][path] = type.to_s
          else
            accumulated[:consts].delete(path)
          end
        end
      end

      # Keys common to both, keeping a value only when the two agree (a
      # conflicting proof at entry is dropped conservatively).
      def intersect(a, b)
        (a.keys & b.keys).each_with_object({}) do |k, acc|
          acc[k] = a[k] if a[k] == b[k]
        end
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
              conditional_const_returns: existing.conditional_const_returns.merge(entry.conditional_const_returns),
              establishes_consts: existing.establishes_consts.merge(entry.establishes_consts),
              delegates_to_instance: existing.delegates_to_instance || entry.delegates_to_instance
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
