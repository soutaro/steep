require_relative "test_helper"

class LSPFormatterTest < Minitest::Test
  include TestHelper
  include Steep

  LSP = LanguageServer::Protocol
  LSPFormatter = Diagnostic::LSPFormatter

  def node
    ::Parser::Ruby33.parse("1+2")
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

  def duplicated_method_definition
    interface_buffer = RBS::Buffer.new(name: Pathname("sig/interface.rbs"), content: <<~RBS)
      interface _HasItems
        def items: () -> Array[Integer]
      end
    RBS
    class_buffer = RBS::Buffer.new(name: Pathname("sig/foo.rbs"), content: <<~RBS)
      class Foo
        include _HasItems
        attr_reader items: Array[Integer]
      end
    RBS

    Diagnostic::Signature::DuplicatedMethodDefinition.new(
      class_name: RBS::TypeName.parse("::Foo"),
      method_name: :items,
      location: RBS::Location.new(class_buffer, 32, 65),
      related_locations: [RBS::Location.new(interface_buffer, 22, 53)]
    )
  end

  def test_format__related_information
    base_dir = Pathname.pwd
    formatter = LSPFormatter.new({}, base_dir: base_dir)

    json = formatter.format(duplicated_method_definition) or raise

    assert_equal(
      { start: { line: 2, character: 2 }, end: { line: 2, character: 35 } },
      json[:range]
    )
    assert_equal(
      [
        {
          location: {
            uri: PathHelper.to_uri(base_dir + "sig/interface.rbs").to_s,
            range: { start: { line: 1, character: 2 }, end: { line: 1, character: 33 } }
          },
          message: "Another definition of `items`"
        }
      ],
      json[:relatedInformation]
    )
  end

  def test_format__related_information__no_base_dir
    formatter = LSPFormatter.new({})

    json = formatter.format(duplicated_method_definition) or raise

    # The URI of the relative path cannot be made
    refute_operator json, :key?, :relatedInformation
  end
end
