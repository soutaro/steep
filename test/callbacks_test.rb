require_relative "test_helper"
require "tmpdir"
require "fileutils"

class CallbacksTest < Minitest::Test
  Callbacks = Steep::Callbacks

  def test_empty_store
    store = Callbacks::Store.empty
    assert_predicate store, :empty?
    assert_empty store.lookup_callbacks_for_method("Foo", :bar)
  end

  def test_parses_single_entry
    raw = {
      "callbacks" => [
        {
          "class" => "PostsController",
          "apply_postcondition_of" => "set_post",
          "runs_before" => ["show", "edit", "update", "destroy", "publish"]
        }
      ]
    }
    store = Callbacks::Store.from_hash(raw, source: "<test>")
    entries = store.lookup_callbacks_for_method("PostsController", :show)

    assert_equal 1, entries.size
    entry = entries.first
    assert_equal "PostsController", entry.class_name
    assert_equal :set_post, entry.handler_method
    assert_equal [:show, :edit, :update, :destroy, :publish], entry.runs_before
    refute entry.singleton
  end

  def test_lookup_filters_by_method
    raw = {
      "callbacks" => [
        {
          "class" => "PostsController",
          "apply_postcondition_of" => "set_post",
          "runs_before" => ["show", "edit"]
        }
      ]
    }
    store = Callbacks::Store.from_hash(raw, source: "<test>")

    assert_equal 1, store.lookup_callbacks_for_method("PostsController", :show).size
    assert_equal 1, store.lookup_callbacks_for_method("PostsController", :edit).size
    assert_empty store.lookup_callbacks_for_method("PostsController", :index)
  end

  def test_lookup_strips_leading_colons
    raw = {
      "callbacks" => [
        { "class" => "PostsController", "apply_postcondition_of" => "set_post", "runs_before" => ["show"] }
      ]
    }
    store = Callbacks::Store.from_hash(raw, source: "<test>")

    assert_equal 1, store.lookup_callbacks_for_method("::PostsController", :show).size
    assert_equal 1, store.lookup_callbacks_for_method("PostsController", :show).size
  end

  def test_multiple_entries_for_same_class_aggregate
    raw = {
      "callbacks" => [
        { "class" => "PostsController", "apply_postcondition_of" => "set_post", "runs_before" => ["show"] },
        { "class" => "PostsController", "apply_postcondition_of" => "authenticate", "runs_before" => ["show", "index"] }
      ]
    }
    store = Callbacks::Store.from_hash(raw, source: "<test>")

    entries = store.lookup_callbacks_for_method("PostsController", :show)
    assert_equal 2, entries.size
    handlers = entries.map(&:handler_method)
    assert_equal [:set_post, :authenticate], handlers
  end

  def test_skips_entry_with_missing_fields
    raw = {
      "callbacks" => [
        { "class" => "X" }, # missing apply_postcondition_of and runs_before
        { "apply_postcondition_of" => "y", "runs_before" => ["z"] }, # missing class
        { "class" => "X", "apply_postcondition_of" => "y", "runs_before" => [] }, # empty runs_before
        { "class" => "X", "apply_postcondition_of" => "y" }, # missing runs_before entirely
      ]
    }
    store = Callbacks::Store.from_hash(raw, source: "<test>")
    assert_predicate store, :empty?
  end

  def test_accepts_symbol_strings_in_runs_before
    raw = {
      "callbacks" => [
        { "class" => "X", "apply_postcondition_of" => "y", "runs_before" => ["a", "b"] }
      ]
    }
    store = Callbacks::Store.from_hash(raw, source: "<test>")
    entries = store.lookup_callbacks_for_method("X", :a)
    assert_equal 1, entries.size
    assert_equal [:a, :b], entries.first.runs_before
  end

  def test_singleton_flag
    raw = {
      "callbacks" => [
        { "class" => "X", "apply_postcondition_of" => "y", "runs_before" => ["a"], "singleton" => true }
      ]
    }
    store = Callbacks::Store.from_hash(raw, source: "<test>")
    entry = store.lookup_callbacks_for_method("X", :a).first
    assert entry.singleton
  end

  def test_load_reads_all_sidecars_under_sig
    Dir.mktmpdir do |dir|
      base = Pathname.new(dir)
      FileUtils.mkdir_p(base / "sig/rbs_rails")
      FileUtils.mkdir_p(base / "sig/manual")
      (base / "sig/rbs_rails/.steep_callbacks.yml").write(
        YAML.dump("callbacks" => [
          { "class" => "PostsController", "apply_postcondition_of" => "set_post", "runs_before" => ["show", "edit"] }
        ])
      )
      (base / "sig/manual/.steep_callbacks.yml").write(
        YAML.dump("callbacks" => [
          { "class" => "PostsController", "apply_postcondition_of" => "extra", "runs_before" => ["show"] },
          { "class" => "UsersController", "apply_postcondition_of" => "set_user", "runs_before" => ["show", "edit"] }
        ])
      )

      store = Callbacks.load(base)

      posts_show = store.lookup_callbacks_for_method("PostsController", :show)
      assert_equal 2, posts_show.size
      # Files are loaded in glob-sorted order — `sig/manual/...` precedes
      # `sig/rbs_rails/...` alphabetically, so `extra` entries come first.
      assert_equal Set[:set_post, :extra], posts_show.map(&:handler_method).to_set

      assert_equal 1, store.lookup_callbacks_for_method("UsersController", :edit).size
      assert_empty store.lookup_callbacks_for_method("Other", :foo)
    end
  end

  def test_load_returns_empty_when_no_sidecar
    Dir.mktmpdir do |dir|
      store = Callbacks.load(Pathname.new(dir))
      assert_predicate store, :empty?
    end
  end
end
