module Steep
  module Contracts
    # Whole-program analysis that decides, for each inferred precondition
    # contract, whether it is actually *enforced* by its call sites.
    #
    # A contract is enforced only when every statically visible call site
    # satisfies the precondition AND at least one such call site exists. A
    # method with zero static call sites (the typical Rails action / mailer /
    # job called by the framework) is NOT enforced: nobody checks the
    # precondition, so narrowing it inside the body would silence real bugs.
    #
    # See felixefelip/steep#20.
    class Enforcement
      def self.analyze(project, store)
        new(project, store).analyze
      end

      def initialize(project, store)
        @project = project
        @store = store
      end

      # Whole-program analysis result: the `enforced` flag per contract key,
      # plus the transitive precondition `obligations` (`{ key:, expr: }`)
      # harvested from self-calls that the enclosing method does not satisfy.
      Result = Struct.new(:enforced, :obligations, keyword_init: true)

      # Type-checks the whole program with `@store` loaded and returns a
      # `Result`. `enforced[key]` is true when the contract has at least one
      # static call site and every one satisfies it; `obligations` feeds the
      # Runner's transitive-closure fixpoint.
      def analyze
        observations = Hash.new { |h, k| h[k] = { seen: 0, unsatisfied: 0 } }
        obligations = []

        @project.targets.each do |target|
          collect_for_target(target, observations, obligations)
        end

        enforced = @store.methods.each_key.each_with_object({}) do |key, result|
          obs = observations[key]
          result[key] = obs[:seen] > 0 && obs[:unsatisfied] == 0
        end

        Result.new(enforced: enforced, obligations: obligations)
      end

      private

      def collect_for_target(target, observations, obligations)
        loader = Project::Target.construct_env_loader(options: target.options, project: @project)
        file_loader = Services::FileLoader.new(base_dir: @project.base_dir)

        file_loader.each_path_in_patterns(target.signature_pattern) do |path|
          absolute = @project.absolute_path(path)
          loader.add(path: absolute) if absolute.file?
        end

        signature_service = Services::SignatureService.load_from(loader, implicitly_returns_nil: target.implicitly_returns_nil)
        status = signature_service.status
        return unless status.is_a?(Services::SignatureService::LoadedStatus)

        subtyping = status.subtyping
        resolver = status.constant_resolver

        file_loader.each_path_in_patterns(target.source_pattern) do |path|
          absolute = @project.absolute_path(path)
          next unless absolute.file? && absolute.extname == ".rb"

          text = absolute.read
          source = begin
                     Source.parse(text, path: absolute, factory: subtyping.factory)
                   rescue ::Parser::SyntaxError, AnnotationParser::SyntaxError
                     next
                   end

          # Type-check with the inferred contracts loaded so that
          # check_precondition_at_call_site fires and records observations.
          typing = Services::TypeCheckService.type_check(
            source: source,
            subtyping: subtyping,
            constant_resolver: resolver,
            cursor: nil,
            contracts: @store,
            postconditions: @project.postconditions,
            callbacks: @project.callbacks,
            delegation_registry: @project.delegation_registry,
            constructor_bindings: @project.constructor_binding_registry,
            return_forwarding: @project.return_forwarding_registry,
            return_alias: @project.return_alias_registry
          )

          typing.contract_call_sites.each do |obs|
            bucket = observations[obs[:key]]
            bucket[:seen] += 1
            bucket[:unsatisfied] += 1 unless obs[:satisfied]
          end

          obligations.concat(typing.precondition_obligations)
        end
      end
    end
  end
end
