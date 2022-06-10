require_relative "test_helper"

class ExpectationsTest < Minitest::Test
  include TestHelper
  include ShellHelper
  include Steep

  LSP = LanguageServer::Protocol

  def test_load
    es = Expectations.load(path: Pathname("steep_expectations.yml"), content: <<YAML)
- file: a.rb
  diagnostics:
    - range:
        start: { line: 4, character: 0 }
        end: { line: 4, character: 7 }
      severity: ERROR
      message: |
        Cannot assign a value of type `::String` to a variable of type `::Symbol`
          ::String <: ::Symbol
            ::Object <: ::Symbol
              ::BasicObject <: ::Symbol
      code: Ruby::UnresolvedOverloading
YAML

    assert_equal(
      [
        {
          range: {
            start: { line: 3, character: 0 },
            end: { line: 3, character: 7 }
          },
          severity: LSP::Constant::DiagnosticSeverity::ERROR,
          code: "Ruby::UnresolvedOverloading",
          message: <<~MSG
            Cannot assign a value of type `::String` to a variable of type `::Symbol`
              ::String <: ::Symbol
                ::Object <: ::Symbol
                  ::BasicObject <: ::Symbol
          MSG
        }
      ],
      es.diagnostics[Pathname("a.rb")]
    )
  end

  def test_testresult
    ds = [
      {
        range: {
          start: { line: 3, character: 0 },
          end: { line: 3, character: 7 }
        },
        severity: LSP::Constant::DiagnosticSeverity::ERROR,
        code: "Ruby::UnresolvedOverloading",
        message: "Diagnostic 1"
      },
      {
        range: {
          start: { line: 3, character: 3 },
          end: { line: 3, character: 7 }
        },
        severity: LSP::Constant::DiagnosticSeverity::ERROR,
        code: "Ruby::UnresolvedOverloading",
        message: "Diagnostic 2"
      },
      {
        range: {
          start: { line: 4, character: 0 },
          end: { line: 5, character: 0 }
        },
        severity: LSP::Constant::DiagnosticSeverity::ERROR,
        code: "Ruby::UnresolvedOverloading",
        message: "Diagnostic 3"
      }
    ]

    result = Expectations::TestResult.new(
      path: Pathname("foo.rb"),
      expectation: ds[0..1],
      actual: ds[1..2]
    )

    refute_predicate result, :empty?
    refute_predicate result, :satisfied?

    assert_equal [ds[1]], result.expected_diagnostics
    assert_equal [ds[0]], result.missing_diagnostics
    assert_equal [ds[2]], result.unexpected_diagnostics
  end
end
