module Steep
  module Drivers
    class SignatureErrorPrinter
      attr_reader :stdout
      attr_reader :stderr

      def initialize(stdout:, stderr:)
        @stdout = stdout
        @stderr = stderr
      end

      def print_syntax_errors(errors)
        errors.each do |error|
          stderr.puts error.message
        end
      end

      def print_semantic_errors(errors)
        errors.each do |error|
          error.puts stderr
        end
      end
    end
  end
end
