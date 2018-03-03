module Steep
  module Drivers
    class Check
      attr_reader :source_paths
      attr_reader :signature_dirs
      attr_reader :stdout
      attr_reader :stderr

      attr_accessor :verbose
      attr_accessor :accept_implicit_any
      attr_accessor :dump_all_types
      attr_accessor :fallback_any_is_error

      attr_reader :labeling

      include Utils::EachSignature

      def initialize(source_paths:, signature_dirs:, stdout:, stderr:)
        @source_paths = source_paths
        @signature_dirs = signature_dirs
        @stdout = stdout
        @stderr = stderr

        self.verbose = false
        self.accept_implicit_any = false
        self.dump_all_types = false
        self.fallback_any_is_error = false

        @labeling = ASTUtils::Labeling.new
      end

      def run
        Steep.logger.level = Logger::DEBUG if verbose

        env = AST::Signature::Env.new

        each_signature(signature_dirs, verbose) do |signature|
          env.add signature
        end

        builder = Interface::Builder.new(signatures: env)
        check = Subtyping::Check.new(builder: builder)

        validator = Utils::Validator.new(stdout: stdout, stderr: stderr, verbose: verbose)

        validated = validator.run(env: env, builder: builder, check: check) do |sig|
          stderr.puts "Validating #{sig.name} (#{sig.location.name}:#{sig.location.start_line})..." if verbose
        end

        unless validated
          return 1
        end

        sources = []
        each_ruby_source(source_paths, verbose) do |source|
          sources << source
        end

        typing = Typing.new

        sources.each do |source|
          Steep.logger.tagged source.path do
            Steep.logger.debug "Typechecking..."
            annotations = source.annotations(block: source.node) || []

            pp annotations if verbose

            construction = TypeConstruction.new(
              checker: check,
              annotations: annotations,
              source: source,
              var_types: {},
              self_type: nil,
              block_context: nil,
              module_context: TypeConstruction::ModuleContext.new(
                instance_type: nil,
                module_type: nil,
                const_types: annotations.const_types,
                implement_name: nil,
                current_namespace: nil,
                const_env: TypeInference::ConstantEnv.new(builder: check.builder, current_namespace: nil)
              ),
              method_context: nil,
              typing: typing,
              )
            construction.synthesize(source.node)
          end
        end

        if dump_all_types
          lines = []

          typing.nodes.each_value do |node|
            begin
              type = typing.type_of(node: node)
              lines << [node.loc.expression.source_buffer.name, [node.loc.last_line,node.loc.last_column], [node.loc.first_line, node.loc.column], node, type]
            rescue
              lines << [node.loc.expression.source_buffer.name, [node.loc.last_line,node.loc.last_column], [node.loc.first_line, node.loc.column], node, nil]
            end
          end

          lines.sort {|x,y| y <=> x }.reverse_each do |line|
            source = line[3].loc.expression.source
            stdout.puts "#{line[0]}:(#{line[2].join(",")}):(#{line[1].join(",")}):\t#{line[3].type}:\t#{line[4]}\t(#{source.split(/\n/).first})"
          end
        end

        typing.errors.each do |error|
          next if error.is_a?(Errors::FallbackAny) && !fallback_any_is_error
          error.print_to stdout
        end
      end
    end
  end
end
