module Steep
  module Drivers
    class DiagnosticPrinter
      # https://docs.github.com/en/actions/writing-workflows/choosing-what-your-workflow-does/workflow-commands-for-github-actions
      class GitHubActionsFormatter < BaseFormatter
        ESCAPE_MAP = { '%' => '%25', "\n" => '%0A', "\r" => '%0D' }.freeze

        def print(diagnostic, prefix: "", source: true)
          stdout.printf(
            "::%<severity>s file=%<file>s,line=%<line>d,endLine=%<endLine>d,col=%<column>d,endColumn=%<endColumn>d::%<message>s",
            severity: github_severity(diagnostic[:severity]),
            file: path,
            line: diagnostic[:range][:start][:line] + 1,
            endLine: diagnostic[:range][:end][:line] + 1,
            column: diagnostic[:range][:start][:character],
            endColumn: diagnostic[:range][:end][:character],
            message: github_escape("[#{diagnostic[:code]}] #{diagnostic[:message]}")
          )
        end

        private

        def github_severity(severity)
          case severity
          when LSP::Constant::DiagnosticSeverity::ERROR
            "error"
          when LSP::Constant::DiagnosticSeverity::WARNING
            "warning"
          when LSP::Constant::DiagnosticSeverity::INFORMATION
            "notice"
          when LSP::Constant::DiagnosticSeverity::HINT
            "notice"
          else
            raise
          end
        end

        def github_escape(string)
          string.gsub(Regexp.union(ESCAPE_MAP.keys), ESCAPE_MAP)
        end
      end
    end
  end
end
