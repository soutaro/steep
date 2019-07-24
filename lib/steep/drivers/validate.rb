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
        loader.stdlib_root = nil if signature_options.no_builtin
        signature_options.library_paths.each do |path|
          loader.add(path: path)
        end
        signature_options.signature_paths.each do |path|
          loader.add(path: path)
        end

        env = Ruby::Signature::Environment.new()
        loader.load(env: env)

        project = Project.new(environment: env)
        project.reload_signature

        case project.signature
        when Project::SignatureHasSyntaxError
          project.signature.errors.each do |error|
            stderr.puts error.message
          end
          1
        when Project::SignatureHasError
          project.signature.errors.each do |error|
            error.puts stderr
          end
          1
        else
          0
        end
      end
    end
  end
end
