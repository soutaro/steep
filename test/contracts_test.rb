require_relative "test_helper"

class ContractsTest < Minitest::Test
  Contracts = Steep::Contracts

  def test_empty_store
    store = Contracts::Store.empty
    assert_predicate store, :empty?
    assert_nil store.lookup_instance("Foo", :bar)
    assert_nil store.lookup_singleton("Foo", :bar)
  end

  def test_parses_instance_method_with_chain
    raw = {
      "version" => 1,
      "methods" => {
        "Foo#bar" => {
          "requires" => [
            { "kind" => "not_nil",
              "expr" => { "kind" => "send",
                          "receiver" => { "kind" => "self" },
                          "method" => "foo",
                          "chain" => ["name"] } }
          ]
        }
      }
    }
    store = Contracts::Store.from_hash(raw, source: "<test>")
    contract = store.lookup_instance("Foo", :bar)

    refute_nil contract
    assert_equal :bar, contract.method_name
    refute contract.singleton
    assert_equal 1, contract.requires.size

    req = contract.requires[0]
    assert_instance_of Contracts::Predicate::NotNil, req

    expr = req.expr
    assert_instance_of Contracts::Expr::Send, expr
    assert_instance_of Contracts::Expr::SelfRef, expr.receiver
    assert_equal :foo, expr.method
    assert_equal [:name], expr.chain
  end

  def test_enforced_defaults_to_true_when_absent
    raw = {
      "methods" => {
        "Foo#bar" => {
          "requires" => [
            { "kind" => "not_nil", "expr" => { "kind" => "send", "receiver" => { "kind" => "self" }, "method" => "name" } }
          ]
        }
      }
    }
    contract = Contracts::Store.from_hash(raw, source: "<test>").lookup_instance("Foo", :bar)
    assert contract.enforced, "missing `enforced` must default to true (back-compat)"
  end

  def test_parses_enforced_false
    raw = {
      "methods" => {
        "Foo#bar" => {
          "enforced" => false,
          "requires" => [
            { "kind" => "not_nil", "expr" => { "kind" => "send", "receiver" => { "kind" => "self" }, "method" => "name" } }
          ]
        }
      }
    }
    contract = Contracts::Store.from_hash(raw, source: "<test>").lookup_instance("Foo", :bar)
    refute contract.enforced
  end

  def test_parses_singleton_method
    raw = {
      "methods" => {
        "Foo.bar" => {
          "requires" => [
            { "kind" => "not_nil",
              "expr" => { "kind" => "send", "receiver" => { "kind" => "self" }, "method" => "name" } }
          ]
        }
      }
    }
    store = Contracts::Store.from_hash(raw, source: "<test>")
    assert_nil store.lookup_instance("Foo", :bar)
    contract = store.lookup_singleton("Foo", :bar)
    refute_nil contract
    assert contract.singleton
  end

  def test_unsupported_version_yields_empty_store
    raw = { "version" => 99, "methods" => { "Foo#bar" => { "requires" => [] } } }
    store = Contracts::Store.from_hash(raw, source: "<test>")
    assert_predicate store, :empty?
  end

  def test_invalid_method_key_is_ignored
    raw = {
      "methods" => {
        "lowercase_no_separator" => {
          "requires" => [
            { "kind" => "not_nil", "expr" => { "kind" => "send", "receiver" => { "kind" => "self" }, "method" => "name" } }
          ]
        }
      }
    }
    store = Contracts::Store.from_hash(raw, source: "<test>")
    assert_predicate store, :empty?
  end

  def test_unknown_predicate_kind_drops_method
    raw = {
      "methods" => {
        "Foo#bar" => {
          "requires" => [{ "kind" => "wat" }]
        }
      }
    }
    store = Contracts::Store.from_hash(raw, source: "<test>")
    assert_predicate store, :empty?
  end

  def test_unknown_expr_kind_drops_predicate
    raw = {
      "methods" => {
        "Foo#bar" => {
          "requires" => [
            { "kind" => "not_nil", "expr" => { "kind" => "garbage" } }
          ]
        }
      }
    }
    store = Contracts::Store.from_hash(raw, source: "<test>")
    assert_predicate store, :empty?
  end

  def test_load_returns_empty_when_file_missing
    Dir.mktmpdir do |dir|
      store = Contracts.load(Pathname(dir))
      assert_predicate store, :empty?
    end
  end

  def test_load_reads_yaml_from_disk
    Dir.mktmpdir do |dir|
      base = Pathname(dir)
      target = base + Contracts::DEFAULT_SIDECAR_PATH
      target.parent.mkpath
      target.write(<<~YAML)
        version: 1
        methods:
          "Foo#bar":
            requires:
              - kind: not_nil
                expr:
                  kind: send
                  receiver: { kind: self }
                  method: name
      YAML

      store = Contracts.load(base)
      refute_predicate store, :empty?
      contract = store.lookup_instance("Foo", :bar)
      refute_nil contract
      assert_equal :name, contract.requires[0].expr.method
    end
  end
end
