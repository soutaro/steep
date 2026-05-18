module Steep
  module Contracts
    class Runner
      def self.run(project)
        new(project).run
      end

      def initialize(project)
        @project = project
      end

      def run
        contracts = []
        @project.targets.each do |target|
          contracts.concat(infer_for_target(target))
        end
        merge(contracts)
      end

      def output_path
        @project.absolute_path(Pathname(DEFAULT_SIDECAR_PATH))
      end

      def write(contracts)
        if contracts.empty?
          output_path.delete if output_path.file?
        else
          Writer.write(output_path, contracts)
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

          # Real postconditions matter here: with via_receiver / self
          # narrowing in scope, the inferrer can prove nil-safety inside
          # method bodies and *avoid* emitting a precondition the body no
          # longer needs. Always pass the project's loaded store, not
          # `Store.empty` — felixefelip/steep#14 follow-up.
          typing = Services::TypeCheckService.type_check(
            source: source,
            subtyping: subtyping,
            constant_resolver: resolver,
            cursor: nil,
            contracts: Store.empty,
            postconditions: @project.postconditions
          )

          out.concat(Inferrer.infer(source, typing))
        end

        out
      end

      def merge(contracts)
        by_key = {}
        contracts.each do |c|
          key = "#{c.type_name}#{c.singleton ? '.' : '#'}#{c.method_name}"
          if (existing = by_key[key])
            seen = existing.requires.map { |r| predicate_signature(r) }.to_set
            extras = c.requires.reject { |r| seen.include?(predicate_signature(r)) }
            by_key[key] = MethodContract.new(
              type_name: existing.type_name,
              method_name: existing.method_name,
              singleton: existing.singleton,
              requires: existing.requires + extras
            )
          else
            by_key[key] = c
          end
        end
        by_key.values
      end

      def predicate_signature(predicate)
        case predicate
        when Predicate::NotNil then [:not_nil, expr_signature(predicate.expr)]
        end
      end

      def expr_signature(expr)
        case expr
        when Expr::SelfRef then [:self]
        when Expr::Send then [:send, expr_signature(expr.receiver), expr.method, expr.chain]
        end
      end
    end
  end
end
