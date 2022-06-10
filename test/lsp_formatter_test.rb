require "test_helper"

class LSPFormatterTest < Minitest::Test
  include TestHelper
  include Steep

  LSP = LanguageServer::Protocol
  LSPFormatter = Diagnostic::LSPFormatter

  def node
    ::Parser::Ruby31.parse("1+2")
  end

  def test_severity_for
    formatter = LSPFormatter.new(
      {
        Diagnostic::Ruby::FallbackAny => LSPFormatter::INFORMATION
      },
      default_severity: LSPFormatter::ERROR
    )

    assert_equal(
      LSP::Constant::DiagnosticSeverity::INFORMATION,
      formatter.severity_for(
        Diagnostic::Ruby::FallbackAny.new(node: node)
      )
    )

    assert_equal(
      LSP::Constant::DiagnosticSeverity::ERROR,
      formatter.severity_for(
        Diagnostic::Ruby::UnexpectedJump.new(node: node)
      )
    )
  end
end
