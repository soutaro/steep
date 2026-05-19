require_relative "test_helper"

class PostconditionsWriterTest < Minitest::Test
  Postconditions = Steep::Postconditions
  Writer = Postconditions::Writer
  InferredEntry = Postconditions::InferredEntry
  Store = Postconditions::Store

  def build_entry(class_name:, method_name:, ivars:, singleton: false)
    InferredEntry.new(
      class_name: class_name,
      method_name: method_name,
      singleton: singleton,
      ivars: ivars
    )
  end

  def test_dump_serializes_unconditional_ivars
    entry = build_entry(
      class_name: "PCSetterController",
      method_name: :set_company,
      ivars: { :"@company" => Steep::AST::Types::Name::Instance.new(name: RBS::TypeName.parse("::Company").absolute!, args: []) }
    )

    yaml = Writer.dump([entry])
    raw = YAML.safe_load(yaml)

    # Round-trip back through the loader so the test asserts on parsed
    # structure rather than YAML string formatting (which can vary by
    # Psych version).
    store = Store.from_hash(raw, source: "<test>")
    parsed_entry = store.lookup_instance("PCSetterController", :set_company)

    refute_nil parsed_entry, "expected entry to round-trip through the loader"
    refute_nil parsed_entry.unconditional, "expected unconditional branch to be present"
    assert_equal({ :"@company" => "::Company" }, parsed_entry.unconditional.ivar_type_strings)
  end

  def test_dump_sorts_entries_for_deterministic_output
    zeta = build_entry(
      class_name: "ZetaCtrl",
      method_name: :a,
      ivars: { :"@x" => Steep::AST::Types::Name::Instance.new(name: RBS::TypeName.parse("::Integer").absolute!, args: []) }
    )
    alpha = build_entry(
      class_name: "AlphaCtrl",
      method_name: :b,
      ivars: { :"@y" => Steep::AST::Types::Name::Instance.new(name: RBS::TypeName.parse("::String").absolute!, args: []) }
    )

    yaml = Writer.dump([zeta, alpha])
    alpha_pos = yaml.index("AlphaCtrl") or flunk("AlphaCtrl not found")
    zeta_pos = yaml.index("ZetaCtrl") or flunk("ZetaCtrl not found")
    assert alpha_pos < zeta_pos, "expected AlphaCtrl to be emitted before ZetaCtrl for deterministic output"
  end

  def test_dump_serializes_ivar_keys_in_alphabetical_order
    entry = build_entry(
      class_name: "MultiIvar",
      method_name: :setup,
      ivars: {
        :"@zeta" => Steep::AST::Types::Name::Instance.new(name: RBS::TypeName.parse("::String").absolute!, args: []),
        :"@alpha" => Steep::AST::Types::Name::Instance.new(name: RBS::TypeName.parse("::Integer").absolute!, args: [])
      }
    )

    yaml = Writer.dump([entry])

    alpha_pos = yaml.index("@alpha") or flunk("@alpha not found")
    zeta_pos = yaml.index("@zeta") or flunk("@zeta not found")
    assert alpha_pos < zeta_pos, "expected @alpha to be emitted before @zeta"
  end
end
