require_relative "test_helper"

class ContractsWriterTest < Minitest::Test
  Contracts = Steep::Contracts

  def build_store_with(raw)
    Contracts::Store.from_hash(raw, source: "<test>")
  end

  def test_dump_omits_enforced_when_true_and_emits_when_false
    enforced = Contracts::MethodContract.new(
      type_name: "Foo", method_name: :a, singleton: false, enforced: true,
      requires: [Contracts::Predicate::NotNil.new(Contracts::Expr::Send.new(receiver: Contracts::Expr::SelfRef.instance, method: :x, chain: []))]
    )
    unenforced = enforced.with_enforced(false)

    payload = YAML.safe_load(Contracts::Writer.dump([enforced]))
    refute payload.dig("methods", "Foo#a").key?("enforced"),
           "enforced=true is the default and must be omitted from the sidecar"

    payload = YAML.safe_load(Contracts::Writer.dump([unenforced]))
    assert_equal false, payload.dig("methods", "Foo#a", "enforced")

    reparsed = Contracts::Store.from_hash(payload, source: "<test>")
    refute reparsed.lookup_instance("Foo", :a).enforced, "enforced=false must round-trip"
  end

  def test_dump_round_trip_with_chain
    raw = {
      "version" => 1,
      "methods" => {
        "Foo#bar" => {
          "requires" => [
            { "kind" => "not_nil",
              "expr" => { "kind" => "send", "receiver" => { "kind" => "self" }, "method" => "foo", "chain" => ["name"] } }
          ]
        }
      }
    }
    contracts = build_store_with(raw).methods.values
    yaml = Contracts::Writer.dump(contracts)
    reparsed = build_store_with(YAML.safe_load(yaml))

    assert_equal ["Foo#bar"], reparsed.methods.keys
    req = reparsed.methods["Foo#bar"].requires.first
    assert_instance_of Contracts::Predicate::NotNil, req
    assert_equal :foo, req.expr.method
    assert_equal [:name], req.expr.chain
  end

  def test_dump_sorts_methods_for_deterministic_output
    raw = {
      "version" => 1,
      "methods" => {
        "Zeta#a" => {
          "requires" => [
            { "kind" => "not_nil", "expr" => { "kind" => "send", "receiver" => { "kind" => "self" }, "method" => "x" } }
          ]
        },
        "Alpha#b" => {
          "requires" => [
            { "kind" => "not_nil", "expr" => { "kind" => "send", "receiver" => { "kind" => "self" }, "method" => "y" } }
          ]
        }
      }
    }
    contracts = build_store_with(raw).methods.values
    yaml = Contracts::Writer.dump(contracts)

    alpha_pos = yaml.index("Alpha#b") or flunk("Alpha#b not found")
    zeta_pos = yaml.index("Zeta#a") or flunk("Zeta#a not found")
    assert alpha_pos < zeta_pos, "expected Alpha to be emitted before Zeta"
  end

  def test_dump_omits_chain_when_empty
    raw = {
      "version" => 1,
      "methods" => {
        "Foo#bar" => {
          "requires" => [
            { "kind" => "not_nil", "expr" => { "kind" => "send", "receiver" => { "kind" => "self" }, "method" => "name" } }
          ]
        }
      }
    }
    contracts = build_store_with(raw).methods.values
    yaml = Contracts::Writer.dump(contracts)

    refute_includes yaml, "chain"
  end

  def test_dump_singleton_separator
    raw = {
      "methods" => {
        "Foo.bar" => {
          "requires" => [
            { "kind" => "not_nil", "expr" => { "kind" => "send", "receiver" => { "kind" => "self" }, "method" => "x" } }
          ]
        }
      }
    }
    contracts = build_store_with(raw).methods.values
    yaml = Contracts::Writer.dump(contracts)
    parsed = YAML.safe_load(yaml)
    assert_includes parsed["methods"].keys, "Foo.bar"
  end

  def test_write_to_disk_creates_parent_directory
    Dir.mktmpdir do |dir|
      raw = {
        "methods" => {
          "Foo#bar" => {
            "requires" => [
              { "kind" => "not_nil", "expr" => { "kind" => "send", "receiver" => { "kind" => "self" }, "method" => "x" } }
            ]
          }
        }
      }
      contracts = build_store_with(raw).methods.values
      path = Pathname(dir) + "deep/nested/.steep_contracts.yml"
      Contracts::Writer.write(path, contracts)

      assert path.file?, "expected file at #{path}"
      reparsed = build_store_with(YAML.safe_load(path.read))
      assert_equal ["Foo#bar"], reparsed.methods.keys
    end
  end
end
