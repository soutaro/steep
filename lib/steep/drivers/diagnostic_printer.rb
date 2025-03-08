module Steep
  module Drivers
    class DiagnosticPrinter

      LSP = LanguageServer::Protocol

      attr_reader :stdout
      attr_reader :buffer

      def initialize(stdout:, buffer:, formatter: 'code')
        @stdout = stdout
        @buffer = buffer
        @formatter = case formatter
        when 'code'
          CodeFormatter.new(stdout: stdout, buffer: buffer)
        when 'github'
          GitHubActionsFormatter.new(stdout: stdout, buffer: buffer)
        else
          raise "Unknown formatter: #{formatter}"
        end
      end

      def print(diagnostic, prefix: "", source: true)
        @formatter.print(diagnostic, prefix: prefix, source: source)
      end
    end
  end
end
