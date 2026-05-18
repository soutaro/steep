require_relative "test_helper"
require "tmpdir"
require "fileutils"

class PostconditionsTest < Minitest::Test
  Postconditions = Steep::Postconditions

  def test_empty_store
    store = Postconditions::Store.empty
    assert_predicate store, :empty?
    assert_nil store.lookup_instance("Foo", :bar)
  end

  def test_parses_instance_entry
    raw = {
      "postconditions" => [
        {
          "class" => "OrderImport",
          "method" => "shipment?",
          "when_true" => { "self" => "OrderImport & OrderImport::ValidatedAsShipment" }
        }
      ]
    }
    store = Postconditions::Store.from_hash(raw, source: "<test>")
    entry = store.lookup_instance("OrderImport", :shipment?)

    refute_nil entry
    assert_equal "OrderImport", entry.class_name
    assert_equal :shipment?, entry.method_name
    refute_nil entry.when_true
    assert_nil entry.when_false
    assert_equal "OrderImport & OrderImport::ValidatedAsShipment", entry.when_true.self_type_string
  end

  def test_parses_both_branches
    raw = {
      "postconditions" => [
        {
          "class" => "Foo",
          "method" => "valid?",
          "when_true" => { "self" => "Foo & Foo::Validated" },
          "when_false" => { "self" => "Foo" }
        }
      ]
    }
    store = Postconditions::Store.from_hash(raw, source: "<test>")
    entry = store.lookup_instance("Foo", :valid?)

    refute_nil entry.when_true
    refute_nil entry.when_false
  end

  def test_lookup_absolute_type_name_strips_double_colon
    raw = { "postconditions" => [{ "class" => "Foo", "method" => "ok?", "when_true" => { "self" => "Foo" } }] }
    store = Postconditions::Store.from_hash(raw, source: "<test>")
    refute_nil store.lookup_instance("::Foo", :ok?)
    refute_nil store.lookup_instance("Foo", :ok?)
  end

  def test_duplicate_entries_first_wins
    raw = {
      "postconditions" => [
        { "class" => "X", "method" => "go?", "when_true" => { "self" => "X & X::A" } },
        { "class" => "X", "method" => "go?", "when_true" => { "self" => "X & X::B" } }
      ]
    }
    store = Postconditions::Store.from_hash(raw, source: "<test>")
    entry = store.lookup_instance("X", :go?)
    assert_equal "X & X::A", entry.when_true.self_type_string
  end

  def test_skips_entries_missing_both_branches
    raw = {
      "postconditions" => [
        { "class" => "X", "method" => "go?" }
      ]
    }
    store = Postconditions::Store.from_hash(raw, source: "<test>")
    assert_predicate store, :empty?
  end

  def test_branch_rbs_type_caches_parse
    branch = Postconditions::Branch.new(self_type_string: "Foo & Foo::Validated")
    parsed = branch.rbs_type
    assert_kind_of RBS::Types::Intersection, parsed
    assert_same parsed, branch.rbs_type
  end

  def test_branch_rbs_type_returns_nil_on_invalid_string
    branch = Postconditions::Branch.new(self_type_string: "@@invalid syntax")
    assert_nil branch.rbs_type
  end

  def test_load_merges_multiple_sidecars_under_sig
    Dir.mktmpdir do |dir|
      base = Pathname.new(dir)
      FileUtils.mkdir_p(base / "sig/rbs_rails")
      FileUtils.mkdir_p(base / "sig/manual")
      (base / "sig/rbs_rails/.steep_postconditions.yml").write(
        YAML.dump("postconditions" => [
          { "class" => "Foo", "method" => "ok?", "when_true" => { "self" => "Foo & Foo::A" } }
        ])
      )
      (base / "sig/manual/.steep_postconditions.yml").write(
        YAML.dump("postconditions" => [
          { "class" => "Bar", "method" => "ready?", "when_true" => { "self" => "Bar & Bar::Validated" } }
        ])
      )

      store = Postconditions.load(base)
      refute_predicate store, :empty?
      refute_nil store.lookup_instance("Foo", :ok?)
      refute_nil store.lookup_instance("Bar", :ready?)
    end
  end

  def test_load_returns_empty_when_no_sidecar_present
    Dir.mktmpdir do |dir|
      store = Postconditions.load(Pathname.new(dir))
      assert_predicate store, :empty?
    end
  end

  def test_parses_via_receiver
    raw = {
      "postconditions" => [
        {
          "class" => "Inner",
          "method" => "ready?",
          "when_true" => {
            "self" => "Inner & Inner::Ready",
            "via_receiver" => [
              { "through" => "Host#inner", "as" => "Host & Host::Refined" }
            ]
          }
        }
      ]
    }
    store = Postconditions::Store.from_hash(raw, source: "<test>")
    entry = store.lookup_instance("Inner", :ready?)

    refute_nil entry
    assert_equal "Inner & Inner::Ready", entry.when_true.self_type_string
    assert_equal 1, entry.when_true.via_receivers.size

    via = entry.when_true.via_receivers.first
    assert_equal "Host#inner", via.through_string
    assert_equal "Host & Host::Refined", via.as_type_string
    assert_equal :inner, via.through_method_name
    assert_equal RBS::TypeName.parse("::Host"), via.through_type_name
  end

  def test_parses_via_receiver_only_branch_without_self
    raw = {
      "postconditions" => [
        {
          "class" => "Inner",
          "method" => "ready?",
          "when_true" => {
            "via_receiver" => [
              { "through" => "Host#inner", "as" => "Host" }
            ]
          }
        }
      ]
    }
    store = Postconditions::Store.from_hash(raw, source: "<test>")
    entry = store.lookup_instance("Inner", :ready?)

    refute_nil entry
    assert_nil entry.when_true.self_type_string
    assert_equal 1, entry.when_true.via_receivers.size
  end

  def test_via_receiver_skipped_when_through_missing_hash_sign
    raw = {
      "postconditions" => [
        {
          "class" => "Inner",
          "method" => "ready?",
          "when_true" => {
            "self" => "Inner",
            "via_receiver" => [
              { "through" => "Host_no_hash_sign", "as" => "Host" }
            ]
          }
        }
      ]
    }
    store = Postconditions::Store.from_hash(raw, source: "<test>")
    entry = store.lookup_instance("Inner", :ready?)
    refute_nil entry
    assert_empty entry.when_true.via_receivers
  end

  def test_via_receiver_caches_rbs_type
    via = Postconditions::ViaReceiver.new(
      through_string: "Host#inner",
      as_type_string: "Host & Host::Refined"
    )
    parsed = via.as_rbs_type
    assert_kind_of RBS::Types::Intersection, parsed
    assert_same parsed, via.as_rbs_type
  end

  def test_load_skips_invalid_yaml
    Dir.mktmpdir do |dir|
      base = Pathname.new(dir)
      FileUtils.mkdir_p(base / "sig/broken")
      FileUtils.mkdir_p(base / "sig/good")
      (base / "sig/broken/.steep_postconditions.yml").write("not: : valid: yaml")
      (base / "sig/good/.steep_postconditions.yml").write(
        YAML.dump("postconditions" => [
          { "class" => "Foo", "method" => "ok?", "when_true" => { "self" => "Foo" } }
        ])
      )

      store = Postconditions.load(base)
      refute_nil store.lookup_instance("Foo", :ok?)
    end
  end
end
