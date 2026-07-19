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
end
