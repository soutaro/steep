module Steep
  module Drivers
    class Validate
      attr_reader :signature_dirs
      attr_reader :stdout
      attr_reader :stderr
      attr_accessor :verbose

      def initialize(signature_dirs:, stdout:, stderr:)
        @signature_dirs = signature_dirs
        @stdout = stdout
        @stderr = stderr

        self.verbose = false
      end

      include Utils::EachSignature

      def run
        env = AST::Signature::Env.new

        each_signature(signature_dirs, verbose) do |signature|
          env.add signature
        end

        builder = Interface::Builder.new(signatures: env)
        check = Subtyping::Check.new(builder: builder)

        validator = Utils::Validator.new(stdout: stdout, stderr: stderr)

        validator.run(env: env, builder: builder, check: check) do |sig|
          stderr.puts "Validating #{sig.name} (#{sig.location.name}:#{sig.location.start_line})..." if verbose
        end
      end
    end
  end
end
