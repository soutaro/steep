require_relative "set_theoretic_helper"

class SetTheoreticEmptinessTest < Minitest::Test
  include SetTheoreticHelper

  include Steep

  # The cases `is_a?` narrowing produces (c1 to c8 of the design notes)

  def test_class_and_module_without_includer_is_empty_in_rbs
    with_sigs do
      assert_empty_in_rbs_verdict inhabitation("(::String | ::Integer) & ::Enumerable[untyped]")
      assert_empty_in_rbs_verdict inhabitation("::Foo & ::Taggable")
      assert_empty_in_rbs_verdict inhabitation("::Taggable & ::Foo")
    end
  end

  def test_module_and_module_without_common_includer_is_empty_in_rbs
    with_sigs do
      assert_empty_in_rbs_verdict inhabitation("::Enumerable[::Integer] & ::Comparable")
      assert_empty_in_rbs_verdict inhabitation("::Taggable & ::Lonely")
    end
  end

  def test_module_with_includer_is_inhabited
    with_sigs do
      assert_inhabited_verdict inhabitation("::Taggable & ::Bar")
      assert_inhabited_verdict inhabitation("::Foo & ::Sortable"), "`Qux < Foo` includes `Sortable`"
      assert_inhabited_verdict inhabitation("::Taggable & ::Sortable"), "`Both` includes both"
      assert_inhabited_verdict inhabitation("::Taggable & ::Oc"), "`Oc` includes `Outer`, which includes `Taggable`"
      assert_inhabited_verdict inhabitation("::Integer & ::Comparable")
    end
  end

  def test_unrelated_classes_are_empty
    with_sigs do
      assert_empty_verdict inhabitation("::String & ::Integer")
      assert_empty_verdict inhabitation("::Foo & ::Bar")
      assert_empty_verdict inhabitation("::Integer & ::Float")
    end
  end

  def test_negated_class
    with_sigs do
      assert_empty_verdict inhabitation("::Numeric & !::Integer & ::Integer")
      assert_empty_verdict inhabitation("(::Integer | ::String) & !::Integer & !::String")
      assert_empty_verdict inhabitation("::Integer & !::Numeric")
      assert_empty_verdict inhabitation("::Integer & !::Comparable"), "Integer includes Comparable"
      assert_empty_verdict inhabitation("::Integer & !::Object")
      assert_inhabited_verdict inhabitation("::Numeric & !::Integer")
      assert_inhabited_verdict inhabitation("::Foo & !::Taggable")
      assert_inhabited_verdict inhabitation("::BasicObject & !::Object")
    end
  end

  def test_lone_module_is_inhabited
    with_sigs do
      assert_inhabited_verdict inhabitation("::Lonely")
      assert_inhabited_verdict inhabitation("::Lonely & !::Foo")
    end
  end

  def test_module_under_class_in_rbs
    with_sigs do
      assert_empty_in_rbs_verdict inhabitation("::Comparable & !::Object"), "every class including Comparable is an Object"
      assert_inhabited_verdict inhabitation("::Comparable & !::Numeric"), "String includes Comparable"
    end
  end

  def test_literals
    with_sigs do
      assert_inhabited_verdict inhabitation("1 & ::Integer")
      assert_inhabited_verdict inhabitation("1 & ::Comparable")
      assert_inhabited_verdict inhabitation("1 & !2")
      assert_inhabited_verdict inhabitation("::Integer & !1")
      assert_inhabited_verdict inhabitation(":a & ::Symbol")
      assert_inhabited_verdict inhabitation('"a" & ::String')

      assert_empty_verdict inhabitation("1 & ::String")
      assert_empty_verdict inhabitation("1 & !1")
      assert_empty_verdict inhabitation("1 & 2")
      assert_empty_verdict inhabitation("1 & !::Integer")
      assert_empty_verdict inhabitation("1 & !::Numeric")
      assert_empty_verdict inhabitation(":a & ::String")

      assert_empty_in_rbs_verdict inhabitation("1 & ::Taggable"), "Integer could be reopened to include Taggable"
    end
  end

  def test_nil_and_booleans
    with_sigs do
      assert_inhabited_verdict inhabitation("nil & ::NilClass")
      assert_inhabited_verdict inhabitation("nil & ::Object")
      assert_inhabited_verdict inhabitation("true & bool")
      assert_inhabited_verdict inhabitation("bool & !true")
      assert_inhabited_verdict inhabitation("::TrueClass & true")

      assert_empty_verdict inhabitation("nil & !::NilClass")
      assert_empty_verdict inhabitation("nil & ::Foo")
      assert_empty_verdict inhabitation("true & false")
      assert_empty_verdict inhabitation("bool & !true & !false")
      assert_empty_verdict inhabitation("::TrueClass & false")
      assert_empty_verdict inhabitation("::Integer & nil")
    end
  end

  def test_singletons
    with_sigs do
      assert_inhabited_verdict inhabitation("singleton(::Foo) & singleton(::Baz)"), "singleton(Baz) <: singleton(Foo)"
      assert_inhabited_verdict inhabitation("singleton(::Foo) & ::Class")
      assert_inhabited_verdict inhabitation("singleton(::Foo) & ::Object")
      assert_inhabited_verdict inhabitation("singleton(::Extending) & ::Taggable")
      assert_inhabited_verdict inhabitation("singleton(::Foo) & !singleton(::Baz)")
      assert_inhabited_verdict inhabitation("singleton(::Taggable) & ::Module")

      assert_empty_verdict inhabitation("singleton(::Foo) & singleton(::Bar)")
      assert_empty_verdict inhabitation("singleton(::Foo) & ::Integer")
      assert_empty_verdict inhabitation("singleton(::Foo) & !::Class")
      assert_empty_verdict inhabitation("singleton(::Baz) & !singleton(::Foo)")
      assert_empty_verdict inhabitation("singleton(::Foo) & 1")

      assert_empty_in_rbs_verdict inhabitation("singleton(::Foo) & ::Taggable")
    end
  end

  def test_generics_covariant
    with_sigs do
      assert_empty_verdict subtyping("::Array[::Integer]", "::Array[::Numeric]")
      assert_empty_verdict subtyping("::Array[::Integer]", "::Enumerable[::Numeric]")
      assert_empty_verdict subtyping("::Box[::Integer]", "::Box[::Numeric]")
      assert_empty_verdict subtyping("::Hash[::Symbol, ::Integer]", "::Hash[::Symbol, ::Numeric]")
      assert_empty_verdict subtyping("::Array[::Integer]", "::Array[::Integer | ::String]")

      assert_inhabited_verdict subtyping("::Array[::Numeric]", "::Array[::Integer]")
      assert_inhabited_verdict subtyping("::Array[::Integer | ::String]", "::Array[::Integer] | ::Array[::String]"), "a mixed array is in neither"
      assert_inhabited_verdict inhabitation("::Array[::Integer] & ::Array[::String]"), "the empty array"
      assert_inhabited_verdict subtyping("::Array[::Integer]", "::Array[::String]")
    end
  end

  def test_generics_contravariant_and_invariant
    with_sigs do
      assert_empty_verdict subtyping("::Sink[::Numeric]", "::Sink[::Integer]")
      assert_inhabited_verdict subtyping("::Sink[::Integer]", "::Sink[::Numeric]")

      assert_empty_verdict subtyping("::Cell[::Integer]", "::Cell[::Integer]")
      assert_empty_verdict subtyping("::Cell[::Integer | ::String]", "::Cell[::String | ::Integer]")
      assert_inhabited_verdict subtyping("::Cell[::Integer]", "::Cell[::Numeric]")
      assert_inhabited_verdict subtyping("::Cell[::Numeric]", "::Cell[::Integer]")
    end
  end

  def test_generics_merge_positive_arguments
    with_sigs do
      # The elements are both Integer and Numeric, so `!Array[Integer]` excludes everything
      assert_empty_verdict inhabitation("::Array[::Integer] & ::Array[::Numeric] & !::Array[::Integer]")
      assert_empty_verdict inhabitation("::Array[::Integer] & ::Enumerable[::Numeric] & !::Enumerable[::Integer]")
    end
  end

  def test_untyped_in_subtyping_mode
    with_sigs do
      assert_empty_verdict subtyping("untyped", "::Integer")
      assert_empty_verdict subtyping("::Integer", "untyped")
      assert_empty_verdict subtyping("::Array[untyped]", "::Array[::Integer]")
      assert_empty_verdict subtyping("::Array[::Integer]", "::Array[untyped]")
      assert_empty_verdict subtyping("::Sink[untyped]", "::Sink[::Integer]")
      assert_empty_verdict subtyping("::Cell[untyped]", "::Cell[::Integer]")
      assert_empty_verdict subtyping("::Cell[::Integer]", "::Cell[untyped]")
    end
  end

  def test_untyped_in_inhabitation_mode
    with_sigs do
      assert_inhabited_verdict inhabitation("untyped")
      assert_inhabited_verdict inhabitation("untyped & !::Integer")
      assert_inhabited_verdict inhabitation("untyped & ::Integer")
      assert_inhabited_verdict inhabitation("::Array[untyped] & !::Array[::Integer]")
      # `Intersection.build` absorbs the other types into `untyped` before the check sees them
      assert_inhabited_verdict inhabitation("untyped & ::Integer & ::String")
    end
  end

  def test_type_variables
    with_sigs do
      bounds = { T: parse_type("::Integer") }
      assert_empty_verdict inhabitation("T & !::Numeric", bounds: bounds)
      assert_empty_verdict inhabitation("T & ::String", bounds: bounds)
      assert_empty_verdict inhabitation("T & !T", bounds: bounds)
      assert_empty_verdict subtyping("T", "::Numeric", bounds: bounds)
      assert_inhabited_verdict inhabitation("T & ::Integer", bounds: bounds)
      assert_inhabited_verdict inhabitation("T & !1", bounds: bounds)

      unbounded = { T: nil }
      assert_empty_verdict inhabitation("T & !T", bounds: unbounded)
      assert_inhabited_verdict inhabitation("T & !::Integer", bounds: unbounded)
      assert_inhabited_verdict inhabitation("::Integer & !T", bounds: unbounded)
      assert_inhabited_verdict subtyping("::Integer", "T", bounds: unbounded)
    end
  end

  def test_aliases
    with_sigs do
      assert_empty_verdict inhabitation("::int_or_str & !::Integer & !::String")
      assert_inhabited_verdict inhabitation("::int_or_str & !::Integer")
      assert_empty_verdict subtyping("::int_or_str", "::Integer | ::String")
      assert_empty_verdict subtyping("::Integer", "::int_or_str")
    end
  end

  def test_recursive_aliases
    with_sigs do
      assert_empty_verdict subtyping("::tree", "::Integer | ::Array[::tree]")
      assert_empty_verdict subtyping("::Array[::tree]", "::tree")
      assert_empty_verdict subtyping("::Array[::Array[::Integer]]", "::tree")
      assert_inhabited_verdict subtyping("::Array[::String]", "::tree")
      assert_empty_verdict subtyping("::alias_a", "::alias_b"), "assumed while unfolding"
    end
  end

  def test_structural_types_are_their_classes
    with_sigs do
      assert_empty_verdict inhabitation("[::Integer, ::String] & ::Integer")
      assert_empty_verdict subtyping("[::Integer, ::String]", "::Array[::Integer | ::String]")
      assert_empty_verdict subtyping("{ a: ::Integer }", "::Hash[::Symbol, ::Integer]")
      assert_empty_verdict subtyping("^() -> void", "::Proc")
      assert_empty_verdict inhabitation("^() -> void & ::Integer")
      assert_empty_verdict subtyping("[::Integer, ::String]", "[::Integer, ::String]")
      assert_inhabited_verdict subtyping("[::Integer, ::String]", "::Array[::Integer]")
    end
  end

  def test_tuples
    with_sigs do
      assert_empty_verdict subtyping("[::Integer, ::String]", "[::Numeric, ::String]")
      assert_empty_verdict subtyping("[::Integer, ::String]", "[::Integer, ::String]")
      assert_empty_verdict subtyping("[1, 2]", "[::Integer, ::Integer]")
      assert_empty_verdict subtyping("[untyped, ::Integer]", "[::String, ::Integer]")
      assert_empty_verdict subtyping("[::Integer, ::String]", "::Array[::Numeric | ::String]")
      assert_empty_verdict subtyping("[::Integer, ::String]", "::Enumerable[::Object]")
      assert_empty_verdict subtyping("[::Integer, ::String] & ::Array[::Numeric | ::String]", "[::Integer, ::String]")

      assert_inhabited_verdict subtyping("[::Integer, ::String]", "[::String, ::Integer]")
      assert_inhabited_verdict subtyping("[::Integer]", "[::Integer, ::Integer]")
      assert_inhabited_verdict subtyping("[::Integer, ::String]", "::Array[::Integer]")
      assert_inhabited_verdict subtyping("::Array[::Integer]", "[::Integer, ::Integer]"), "an array of any length is not a pair"

      assert_empty_verdict inhabitation("[::Integer, ::String] & [::String, ::String]")
      assert_empty_verdict inhabitation("[::Integer] & [::Integer, ::Integer]")
      assert_empty_verdict inhabitation("[bot, ::Integer]")
      assert_empty_verdict inhabitation("[::Integer, ::String] & ::Integer")
      assert_inhabited_verdict inhabitation("[::Integer, ::String] & [::Numeric, top]")
      assert_inhabited_verdict inhabitation("[::Integer, ::String] & ::Array[::Comparable]")
      assert_empty_verdict inhabitation("[::Integer, ::String] & ::Array[::Integer]"), "the String component is not an Integer"

      # The negative tuples are decomposed component by component
      assert_empty_verdict inhabitation("[::Integer | ::String, ::Integer] & ![::Integer, ::Integer] & ![::String, ::Integer]")
      assert_inhabited_verdict inhabitation("[::Integer | ::String, ::Integer] & ![::Integer, ::Integer]")
      assert_empty_verdict inhabitation("[::Integer, ::String] & !::Array[top]")
      assert_inhabited_verdict inhabitation("[::Integer, ::String] & ![::Integer]"), "a pair is not a singleton tuple"
    end
  end

  def test_opaque_atoms
    with_sigs do
      assert_inhabited_verdict inhabitation("::_Quacks & ::Integer")
      assert_inhabited_verdict inhabitation("::Integer & !::_Quacks")
      assert_empty_verdict inhabitation("::_Quacks & !::_Quacks")
      assert_empty_verdict subtyping("::_Quacks", "::_Quacks")
      assert_inhabited_verdict inhabitation("self & !::Integer")
      assert_empty_verdict inhabitation("self & !self")
    end
  end

  def test_top_bot_void
    with_sigs do
      assert_inhabited_verdict inhabitation("top")
      assert_inhabited_verdict inhabitation("void")
      assert_empty_verdict inhabitation("bot")
      assert_empty_verdict inhabitation("top & !top")
      assert_empty_verdict subtyping("::Integer", "top")
      assert_empty_verdict subtyping("bot", "::Integer")
      assert_inhabited_verdict subtyping("top", "::Integer")
    end
  end

  def test_subtyping_api
    with_sigs do
      assert emptiness.subtype(parse_type("::Integer"), parse_type("::Numeric"))
      assert emptiness.subtype(parse_type("::Integer | ::String"), parse_type("::Comparable"))
      refute emptiness.subtype(parse_type("::Numeric"), parse_type("::Integer"))

      # `Foo & Taggable` is empty in RBS only, so it is not a subtype of everything
      verdict = subtyping("::Foo & ::Taggable", "::Bar")
      assert_empty_in_rbs_verdict verdict
      refute emptiness.subtype(parse_type("::Foo & ::Taggable"), parse_type("::Bar"))

      assert_empty_verdict emptiness.disjoint?(parse_type("::String"), parse_type("::Integer"))
      assert_inhabited_verdict emptiness.disjoint?(parse_type("::Numeric"), parse_type("::Integer"))
    end
  end

  def test_verdict_reasons
    with_sigs do
      assert_match(/no class under `::Foo` includes `::Taggable`/, inhabitation("::Foo & ::Taggable").reason)
      assert_match(/have no common instance/, inhabitation("::String & ::Integer").reason)
      assert_nil inhabitation("::Integer").reason
    end
  end

  def test_unknown_mode
    with_sigs do
      assert_raises(ArgumentError) { emptiness.check(parse_type("::Integer"), mode: :unknown) }
    end
  end

  def test_cache_is_for_ground_types_only
    with_sigs do
      bounds = { T: parse_type("::Integer") }
      assert_empty_verdict inhabitation("T & ::String", bounds: bounds)
      assert_inhabited_verdict inhabitation("T & ::String", bounds: { T: parse_type("::String") })
    end
  end
end
