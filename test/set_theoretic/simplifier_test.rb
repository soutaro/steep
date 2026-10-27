require_relative "set_theoretic_helper"

class SetTheoreticSimplifierTest < Minitest::Test
  include SetTheoreticHelper

  include Steep

  def simplifier
    Steep::SetTheoretic::Simplifier.new(emptiness: emptiness)
  end

  def simplify(string, bounds: {})
    simplifier.simplify(parse_type(string, variables: bounds.keys), bounds: bounds).to_s
  end

  def intersect(type, predicate, bounds: {})
    simplifier.intersect(parse_type(type, variables: bounds.keys), parse_type(predicate, variables: bounds.keys), bounds: bounds).to_s
  end

  def test_absorption_of_atoms
    with_sigs do
      assert_equal "::Integer", intersect("::Numeric", "::Integer")
      assert_equal "::Integer", intersect("::Integer", "::Numeric")
      assert_equal "::Array[::Integer]", intersect("::Array[::Integer]", "::Array[untyped]")
      assert_equal "::Array[::Integer]", intersect("::Array[::Integer]", "::Array[top]")
    end
  end

  def test_empty_clauses_are_dropped
    with_sigs do
      assert_equal "::String", intersect("::Integer | ::String", "::String")
      assert_equal "bot", intersect("::Integer", "::String")
      assert_equal "bot", simplify("::Integer & !::Integer")
    end
  end

  def test_negations
    with_sigs do
      assert_equal "::String", intersect("::Integer | ::String", "!::Integer")
      assert_equal "(::Numeric & !::Integer)", intersect("::Numeric", "!::Integer")
      assert_equal "::Integer", intersect("::Integer", "!::String"), "the negation of a disjoint class is dropped"
      assert_equal "::Foo", intersect("::Foo", "!::Taggable"), "no class under Foo includes Taggable in the environment"
      assert_equal "::Taggable", intersect("::Taggable", "!::Foo")
      assert_equal "!::String", intersect("top", "!::String")
      assert_equal "(::Integer & !1)", intersect("::Integer", "!1")
    end
  end

  def test_union_covers_negation
    with_sigs do
      assert_equal "::Numeric", simplify("::Integer | (::Numeric & !::Integer)")
      assert_equal "(::Integer | ::String)", simplify("::Integer | (::String & !::Integer)")
    end
  end

  def test_untyped
    with_sigs do
      assert_equal "::String", intersect("untyped", "::String")
      assert_equal "untyped", intersect("untyped", "!::String")
      assert_equal "untyped", intersect("untyped", "!(nil | false)")
      assert_equal "(::Integer | ::String)", intersect("::Integer | ::String", "!untyped"), "`!untyped` excludes nothing for reachability"
    end
  end

  def test_candidates_keep_the_spelling
    with_sigs do
      int_or_str = parse_type("::int_or_str")
      assert_equal int_or_str, simplifier.intersect(int_or_str, parse_type("!nil"), candidates: [int_or_str])
      optional = parse_type("::Integer?")
      assert_equal optional, simplifier.simplify(optional, candidates: [optional])

      # `untyped` is not equivalent to `String` syntactically
      untyped = parse_type("untyped")
      assert_equal parse_type("::String"), simplifier.intersect(untyped, parse_type("::String"), candidates: [untyped])
    end
  end

  def test_aliases_are_unfolded_lazily
    with_sigs do
      assert_equal "::int_or_str", intersect("::int_or_str", "!nil")
      assert_equal "::String", intersect("::int_or_str", "!::Integer")
      assert_equal "::Integer", intersect("::int_or_str", "::Integer")
      assert_equal "::int_or_str", intersect("::int_or_str", "::Comparable"), "both members include Comparable, so the alias stays"
    end
  end

  def test_type_variables
    with_sigs do
      bounds = { T: parse_type("::Integer") }
      assert_equal "T", intersect("T", "!(nil | false)", bounds: bounds)
      assert_equal "T", intersect("T", "::Numeric", bounds: bounds)
      assert_equal "bot", intersect("T", "::String", bounds: bounds)

      unbounded = { T: nil }
      assert_equal "(T & !::String)", intersect("T", "!::String", bounds: unbounded)
    end
  end

  def test_literals_and_booleans
    with_sigs do
      assert_equal "1", intersect("::Integer", "1")
      assert_equal ":a", intersect("::Symbol | ::String", ":a")
      assert_equal "true", intersect("bool", "!(nil | false)")
      assert_equal "false", intersect("bool", "nil | false")
      assert_equal "::Integer", intersect("::Integer | nil | false", "!(nil | false)")
      assert_equal "(nil | false)", intersect("::Integer | nil | false", "nil | false")
    end
  end
end
