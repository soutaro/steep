module Steep
  module Drivers
    class Validate
      attr_reader :signature_options
      attr_reader :stdout
      attr_reader :stderr

      def initialize(signature_options:, stdout:, stderr:)
        @signature_options = signature_options
        @stdout = stdout
        @stderr = stderr
      end

      include Utils::EachSignature

      def run
        loader = Ruby::Signature::EnvironmentLoader.new()
        signature_options.setup(loader: loader)

        env = Ruby::Signature::Environment.new()
        loader.load(env: env)

        project = Project.new(environment: env)
        project.reload_signature

        printer = SignatureErrorPrinter.new(stdout: stdout, stderr: stderr)

        case project.signature
        when Project::SignatureHasSyntaxError
          printer.print_syntax_errors(project.signature.errors)
          1
        when Project::SignatureHasError
          printer.print_semantic_errors(project.signature.errors)
          1
        else
          0
        end
      end
    end
  end
end
