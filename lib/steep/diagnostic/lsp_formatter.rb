module Steep
  module Diagnostic
    class LSPFormatter
      LSP = LanguageServer::Protocol

      attr_reader :config
      attr_reader :default_severity

      ERROR = :error
      WARNING = :warning
      INFORMATION = :information
      HINT = :hint

      def initialize(config = {}, default_severity: ERROR)
        @config = config
        @default_severity = default_severity

        config.each do |klass, severity|
          validate_severity(klass, severity)
          validate_class(klass)
        end
        validate_severity(:default, default_severity)
      end

      def validate_class(klass)
        unless klass < Diagnostic::Ruby::Base
          raise "Unexpected diagnostics class `#{klass}` given"
        end
      end

      def validate_severity(klass, severity)
        case severity
        when ERROR, WARNING, INFORMATION, HINT, nil
          # ok
        else
          raise "Unexpected severity `#{severity}` is specified for #{klass}"
        end
      end

      def format(diagnostic)
        severity = severity_for(diagnostic)

        if severity
          range = diagnostic.location&.as_lsp_range || raise("#{diagnostic.class} object (#{diagnostic.full_message}) instance must have `#location`")

          {
            message: diagnostic.full_message,
            code: diagnostic.diagnostic_code,
            severity: severity,
            range: range
          }
        end
      end

      def severity_for(diagnostic)
        case config.fetch(diagnostic.class, default_severity)
        when ERROR
          LSP::Constant::DiagnosticSeverity::ERROR
        when WARNING
          LSP::Constant::DiagnosticSeverity::WARNING
        when INFORMATION
          LSP::Constant::DiagnosticSeverity::INFORMATION
        when HINT
          LSP::Constant::DiagnosticSeverity::HINT
        when nil
          nil
        end
      end
    end
  end
end
