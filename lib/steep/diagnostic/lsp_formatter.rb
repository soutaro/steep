module Steep
  module Diagnostic
    class LSPFormatter
      LSP = LanguageServer::Protocol

      def format(diagnostic)
        LSP::Interface::Diagnostic.new(
          message: diagnostic.full_message,
          code: diagnostic.diagnostic_code,
          severity: LSP::Constant::DiagnosticSeverity::ERROR,
          range: diagnostic.location.as_lsp_range
        ).to_hash
      end
    end
  end
end
