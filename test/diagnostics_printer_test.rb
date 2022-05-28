require_relative "test_helper"

class DiagnosticsPrinterTest < Minitest::Test
  DiagnosticPrinter = Steep::Drivers::DiagnosticPrinter
  LSP = LanguageServer::Protocol

  def io
    @io ||= StringIO.new
  end

  def setup
    super
    Rainbow.enabled = true
  end

  def teardown
    super
    Rainbow.enabled = false
  end

  def buffer
    @buffer ||= RBS::Buffer.new(content: <<RUBY, name: Pathname("a.rb"))
class Conference
  attr_reader :name
  attr_reader :year

  def initialize(name:, year:)
    @name = name
    @year = year
  end
end
RUBY
  end

  def test_single_line_message
    printer = DiagnosticPrinter.new(stdout: io, buffer: buffer)

    printer.print({
                    range: {
                      start: { line: 5, character: 4 },
                      end: { line: 5, character: 9 }
                    },
                    severity: LSP::Constant::DiagnosticSeverity::ERROR,
                    message: "Instance variable @name is not defined"
                  })

    assert_equal <<MESSAGE, io.string
#{Rainbow("a.rb:6:4").magenta}: [#{Rainbow("error").red}] #{Rainbow("Instance variable @name is not defined").underline}
│
└     #{Rainbow("@name").red} = name
      ~~~~~
MESSAGE
  end

  def test_multiline_message
    printer = DiagnosticPrinter.new(stdout: io, buffer: buffer)

    printer.print({
                    range: {
                      start: { line: 5, character: 4 },
                      end: { line: 5, character: 9 }
                    },
                    severity: LSP::Constant::DiagnosticSeverity::ERROR,
                    message: [
                      "Instance variable @name is not defined",
                      "Attribute declarations or `@name: untyped` will solve the issue."
                    ].join("\n")
                  })

    assert_equal <<MESSAGE, io.string
#{Rainbow("a.rb:6:4").magenta}: [#{Rainbow("error").red}] #{Rainbow("Instance variable @name is not defined").underline}
│ Attribute declarations or `@name: untyped` will solve the issue.
│
└     #{Rainbow("@name").red} = name
      ~~~~~
MESSAGE
  end

  def test_multiline_source
    printer = DiagnosticPrinter.new(stdout: io, buffer: buffer)

    printer.print({
                    range: {
                      start: { line: 4, character: 2 },
                      end: { line: 7, character: 7 }
                    },
                    severity: LSP::Constant::DiagnosticSeverity::WARNING,
                    message: "Duplicated method definition"
                  })

    assert_equal <<MESSAGE, io.string
#{Rainbow("a.rb:5:2").magenta}: [#{Rainbow("warning").yellow}] #{Rainbow("Duplicated method definition").underline}
│
└   #{Rainbow("def initialize(name:, year:)").yellow}
    ~~~~~~~~~~~~~~~~~~~~~~~~~~~~
MESSAGE
  end
end
