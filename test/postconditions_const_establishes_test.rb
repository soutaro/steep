require_relative "test_helper"

# felixefelip/rbs_infer#71 (piece 2 — the write-site wiring). A singleton setter
# `Const.user = <non-nil>` whose `unconditional.establishes_consts` postcondition
# names a sibling attribute proves `Const.<attr>` non-nil for the rest of the
# frame — the memoized-singleton delegation (`Example3::Foo`: `Foo.user = user`
# makes `Foo.name` non-nil because `def user=` writes `name`).
#
# This exercises ONLY the consumption side: the sidecar is hand-written here.
# Inferring/serializing it (generalizing the `.instance` delegation recognition
# to a memoized `foo_instance`) is the follow-up piece.
class PostconditionsConstEstablishesTest < Minitest::Test
  include TestHelper
  include FactoryHelper
  include SubtypingHelper
  include TypeConstructionHelper

  Postconditions = Steep::Postconditions

  RBS = <<~RBS
    class Foo
      def self.name: () -> String?
      def self.user=: (String value) -> void
    end
  RBS

  # `Foo.user=` establishes `Foo.name` non-nil.
  def establishes_name_store
    Postconditions::Store.from_hash(
      {
        "version" => 1,
        "postconditions" => [
          {
            "class" => "Foo",
            "method" => "user=",
            "unconditional" => {
              "establishes_consts" => { "name" => "::String" }
            }
          }
        ]
      },
      source: "<test>"
    )
  end

  # The `(send (const nil :Foo) :name)` read node — here the trailing statement.
  def last_foo_name_type(source, typing)
    body = source.node # begin(...) or the single trailing node
    node = body.type == :begin ? body.children.last : body
    typing.type_of(node: node)
  end

  # A NESTED constant: `Foo` written inside `module Bar` resolves to `::Bar::Foo`,
  # but its literal source path is just `Foo`. The sidecar (like every
  # `.steep_postconditions.yml`) is keyed by the full class name `Bar::Foo`, so
  # the establishment must be looked up / seeded / read by the RESOLVED name, not
  # the source spelling — the `resolved_const_name_string` path.
  NESTED_RBS = <<~RBS
    module Bar
      class Foo
        def self.name: () -> String?
        def self.user=: (String value) -> void
      end
    end
  RBS

  # `Bar::Foo#user=` establishes `Bar::Foo.name` non-nil — keyed by the full name.
  def nested_establishes_name_store
    Postconditions::Store.from_hash(
      {
        "version" => 1,
        "postconditions" => [
          {
            "class" => "Bar::Foo",
            "method" => "user=",
            "unconditional" => {
              "establishes_consts" => { "name" => "::String" }
            }
          }
        ]
      },
      source: "<test>"
    )
  end

  # The first descendant matching `block`, depth-first.
  def find_descendant(node, &block)
    return nil unless node.is_a?(::Parser::AST::Node)
    return node if block.call(node)
    node.children.each do |child|
      found = find_descendant(child, &block)
      return found if found
    end
    nil
  end

  # The `(send (const nil :Foo) :name)` read node nested inside `module Bar`.
  def nested_foo_name_type(source, typing)
    node = find_descendant(source.node) do |n|
      n.type == :send && n.children[1] == :name &&
        n.children[0].is_a?(::Parser::AST::Node) &&
        n.children[0].type == :const && n.children[0].children[1] == :Foo
    end
    typing.type_of(node: node)
  end

  def test_nested_const_establishes_via_resolved_name
    with_checker(NESTED_RBS) do |checker|
      source = parse_ruby(<<~RUBY)
        module Bar
          Foo.user = "x"
          Foo.name
        end
      RUBY

      with_standard_construction(checker, source, postconditions: nested_establishes_name_store) do |construction, typing|
        construction.synthesize(source.node)
        t = nested_foo_name_type(source, typing)
        assert_equal "::String", t.to_s,
                     "a nested `Foo` (resolving to `::Bar::Foo`) must find its sidecar entry by the resolved full name and narrow `Foo.name`"
      end
    end
  end

  def test_write_establishes_sibling_const_non_nil
    with_checker(RBS) do |checker|
      source = parse_ruby(<<~RUBY)
        Foo.user = "x"
        Foo.name
      RUBY

      with_standard_construction(checker, source, postconditions: establishes_name_store) do |construction, typing|
        construction.synthesize(source.node)
        t = last_foo_name_type(source, typing)
        assert_equal "::String", t.to_s,
                     "after `Foo.user = <non-nil>`, the establishes_consts fact narrows `Foo.name` to non-nil"
      end
    end
  end

  def test_no_sidecar_leaves_const_read_nilable
    with_checker(RBS) do |checker|
      source = parse_ruby(<<~RUBY)
        Foo.user = "x"
        Foo.name
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)
        t = last_foo_name_type(source, typing)
        assert_equal "(::String | nil)", t.to_s,
                     "without the postcondition, `Foo.name` stays nilable"
      end
    end
  end

  # felixefelip/steep#76 (RC3). An establishment for `Const.attr` is not
  # monotonic: a LATER `Const.attr = <nilable>` write to the same attribute
  # invalidates the earlier non-nil fact, so a read after it is nilable again.
  OWN_RBS = <<~RBS
    class Foo
      def self.name: () -> String?
      def self.name=: (String? value) -> void
    end
  RBS

  def own_name_establishes_store
    Postconditions::Store.from_hash(
      {
        "version" => 1,
        "postconditions" => [
          {
            "class" => "Foo",
            "method" => "name=",
            "unconditional" => {
              "establishes_consts" => { "name" => "::String" }
            }
          }
        ]
      },
      source: "<test>"
    )
  end

  def test_nilable_write_invalidates_earlier_establishment
    with_checker(OWN_RBS) do |checker|
      source = parse_ruby(<<~RUBY)
        # @type var maybe: ::String?
        maybe = nil
        Foo.name = "x"
        Foo.name = maybe
        Foo.name
      RUBY

      with_standard_construction(checker, source, postconditions: own_name_establishes_store) do |construction, typing|
        construction.synthesize(source.node)
        t = last_foo_name_type(source, typing)
        assert_equal "(::String | nil)", t.to_s,
                     "a later `Foo.name = <nilable>` must invalidate the earlier establishment"
      end
    end
  end

  def test_nil_write_does_not_establish
    with_checker(RBS) do |checker|
      # `Foo.user = nil` would be a type error against `(String)`, but the point
      # is the establishment gate: a nilable RHS proves nothing. Use a nilable
      # local so the write itself type-checks against a widened setter.
      source = parse_ruby(<<~RUBY)
        # @type var maybe: ::String?
        maybe = nil
        Foo.user = maybe
        Foo.name
      RUBY

      with_standard_construction(checker, source, postconditions: establishes_name_store) do |construction, typing|
        construction.synthesize(source.node)
        t = last_foo_name_type(source, typing)
        assert_equal "(::String | nil)", t.to_s,
                     "a nilable RHS must NOT establish the sibling const non-nil"
      end
    end
  end

  # The memoized-singleton READ/WRITE path. A sibling attribute established
  # non-nil at a `Foo.user = <non-nil>` write can be read back — and written —
  # through the memoized accessor (`Foo.foo_instance.name`) as well as the
  # constant path (`Foo.name`); `foo_instance` is a singleton accessor whose
  # return type IS an instance of `Foo`, so both name the same slot. `name=`
  # takes `String?` on both the singleton and instance so the nilable writes
  # below type-check.
  MEMOIZED_RBS = <<~RBS
    class Foo
      def self.foo_instance: () -> Foo
      def self.name: () -> String?
      def self.user=: (String value) -> void
      def self.name=: (String? value) -> void
      def name: () -> String?
      def name=: (String? value) -> void
    end
  RBS

  # The `(send (send (const nil :Foo) :foo_instance) :name)` read node.
  def foo_instance_name_read_type(source, typing)
    node = find_descendant(source.node) do |n|
      n.type == :send && n.children[1] == :name &&
        n.children[0].is_a?(::Parser::AST::Node) &&
        n.children[0].type == :send && n.children[0].children[1] == :foo_instance
    end
    typing.type_of(node: node)
  end

  def test_read_narrows_sibling_through_memoized_accessor
    with_checker(MEMOIZED_RBS) do |checker|
      source = parse_ruby(<<~RUBY)
        Foo.user = "x"
        Foo.foo_instance.name
      RUBY

      with_standard_construction(checker, source, postconditions: establishes_name_store) do |construction, typing|
        construction.synthesize(source.node)
        t = foo_instance_name_read_type(source, typing)
        assert_equal "::String", t.to_s,
                     "after `Foo.user = <non-nil>`, `Foo.foo_instance.name` narrows to non-nil via the memoized accessor, same slot as `Foo.name`"
      end
    end
  end

  def test_nilable_write_through_accessor_invalidates
    with_checker(MEMOIZED_RBS) do |checker|
      source = parse_ruby(<<~RUBY)
        # @type var maybe: ::String?
        maybe = nil
        Foo.user = "x"
        Foo.foo_instance.name = maybe
        Foo.name
      RUBY

      with_standard_construction(checker, source, postconditions: establishes_name_store) do |construction, typing|
        construction.synthesize(source.node)
        t = last_foo_name_type(source, typing)
        assert_equal "(::String | nil)", t.to_s,
                     "a nilable write through the memoized accessor (`Foo.foo_instance.name = maybe`) must invalidate the `Foo.name` fact established by the sibling `Foo.user =` write"
      end
    end
  end

  def test_nilable_write_to_sibling_established_attr_invalidates
    # The written setter (`name=`) has NO establishes_consts of its own — the
    # `name` fact was proven by the sibling `user=`. Invalidation keys on the
    # WRITTEN attribute, so a `Foo.name = <nilable>` still drops it.
    with_checker(MEMOIZED_RBS) do |checker|
      source = parse_ruby(<<~RUBY)
        # @type var maybe: ::String?
        maybe = nil
        Foo.user = "x"
        Foo.name = maybe
        Foo.name
      RUBY

      with_standard_construction(checker, source, postconditions: establishes_name_store) do |construction, typing|
        construction.synthesize(source.node)
        t = last_foo_name_type(source, typing)
        assert_equal "(::String | nil)", t.to_s,
                     "a nilable write to a sibling-established attr must invalidate it even when the attr's own setter establishes nothing"
      end
    end
  end

  # The pure-send cache gap. The established fact narrows `Foo.name`, but a READ
  # of it also caches the narrowed (non-nil) type in Steep's structurally-keyed
  # pure-send cache. A later nilable write must invalidate THAT cache too, not
  # only the fact — otherwise the stale non-nil cached type wins at the next read
  # (the fact is already gone) and masks the nil. The distinguishing ingredient
  # over `test_nilable_write_to_sibling_established_attr_invalidates` is the
  # intervening narrowed read that populates the cache.
  def test_nilable_write_invalidates_pure_cache_from_intervening_read
    with_checker(MEMOIZED_RBS) do |checker|
      source = parse_ruby(<<~RUBY)
        # @type var maybe: ::String?
        maybe = nil
        Foo.user = "x"     # establishes Foo.name non-nil
        Foo.name           # narrowed read — caches Foo.name non-nil in the pure-send cache
        Foo.name = maybe   # nilable write — must invalidate the fact AND the pure cache
        Foo.name           # must be nilable again
      RUBY

      with_standard_construction(checker, source, postconditions: establishes_name_store) do |construction, typing|
        construction.synthesize(source.node)
        t = last_foo_name_type(source, typing)
        assert_equal "(::String | nil)", t.to_s,
                     "an intervening narrowed read caches `Foo.name` non-nil; a later nilable write must invalidate that pure-send cache, not just the fact"
      end
    end
  end

  # Same gap, reached through the memoized accessor on both the read that
  # populates the cache and the write that must invalidate it — the cached read
  # node is `Foo.foo_instance.name`, keyed by the same-slot base.
  def test_nilable_write_through_accessor_invalidates_pure_cache_from_intervening_read
    with_checker(MEMOIZED_RBS) do |checker|
      source = parse_ruby(<<~RUBY)
        # @type var maybe: ::String?
        maybe = nil
        Foo.user = "x"                 # establishes Foo.name non-nil
        Foo.foo_instance.name          # narrowed read through the accessor — caches non-nil
        Foo.foo_instance.name = maybe  # nilable write through the accessor — must invalidate
        Foo.foo_instance.name          # must be nilable again
      RUBY

      with_standard_construction(checker, source, postconditions: establishes_name_store) do |construction, typing|
        construction.synthesize(source.node)
        # The last statement is the trailing `Foo.foo_instance.name` read.
        t = last_foo_name_type(source, typing)
        assert_equal "(::String | nil)", t.to_s,
                     "a narrowed read then a nilable write, both through the memoized accessor, must invalidate the accessor read's pure-send cache"
      end
    end
  end
end
