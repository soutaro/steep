require_relative "set_theoretic_helper"

class SetTheoreticDNFTest < Minitest::Test
  include SetTheoreticHelper

  include Steep

  DNF = SetTheoretic::DNF

  def normalizer
    SetTheoretic::Normalizer.new(factory: factory)
  end

  def clauses(string)
    normalizer.normalize(parse_type(string)).clauses.map do |clause|
      [clause.positives.map(&:to_s).sort, clause.negatives.map(&:to_s).sort]
    end.sort
  end

  def test_distribution
    with_sigs do
      assert_equal [[["::Foo", "::Integer"], []], [["::Foo", "::String"], []]], clauses("(::Integer | ::String) & ::Foo")
      assert_equal [[["::Foo", "::Integer"], []], [["::Foo", "::String"], []], [["::Bar", "::Integer"], []], [["::Bar", "::String"], []]].sort,
                   clauses("(::Integer | ::String) & (::Foo | ::Bar)")
    end
  end

  def test_de_morgan
    with_sigs do
      assert_equal [[[], ["::Integer", "::String"]]], clauses("!(::Integer | ::String)")
      assert_equal [[[], ["::Integer"]], [[], ["::String"]]], clauses("!(::Integer & ::String)")
      assert_equal [[["::Integer"], ["::String"]]], clauses("::Integer & !::String")
      assert_equal [[["::String"], []], [[], ["::Integer"]]].sort, clauses("!(::Integer & !::String)")
    end
  end

  def test_double_negation_and_contradiction
    with_sigs do
      assert_equal [[["::Integer"], []]], clauses("!!::Integer")
      assert_equal [], clauses("::Integer & !::Integer")
      assert_equal [], clauses("bot")
      assert_equal [[[], []]], clauses("top")
      assert_equal [[[], []]], clauses("void")
      assert_equal [], clauses("!top")
      assert_equal [[[], []]], clauses("!bot")
    end
  end

  def test_booleans_and_builtin_values
    with_sigs do
      assert_equal [[["false"], []], [["true"], []]], clauses("bool")
      assert_equal [[[], ["false", "true"]]], clauses("!bool")
      assert_equal [[["nil"], []]], clauses("::NilClass")
      assert_equal [[["true"], []]], clauses("::TrueClass")
      assert_equal [[["false"], []]], clauses("::FalseClass")
      assert_equal [[["::Foo"], []], [["nil"], []]], clauses("::Foo?")
    end
  end

  def test_alias_expansion
    with_sigs do
      assert_equal [[["::Integer"], []], [["::String"], []]], clauses("::int_or_str")
      assert_equal [[[], ["::Integer", "::String"]]], clauses("!::int_or_str")
      # An alias inside a type argument is an atom until the argument is checked
      assert_equal [[["::Array[::tree]"], []], [["::Integer"], []]], clauses("::tree")
    end
  end

  def test_to_type
    with_sigs do
      type = parse_type("(::Integer & !::String) | ::Foo")
      dnf = normalizer.normalize(type)
      assert_equal parse_type("(::Integer & !::String) | ::Foo").to_s, dnf.to_type.to_s
      assert_equal "((::Integer & !::String) | ::Foo)", dnf.to_s
    end
  end

  def test_negation_type_is_parsed_from_ast
    with_sigs do
      type = AST::Types::Intersection.build(types: [parse_type("::Integer"), negation(parse_type("::String | ::Symbol"))])
      dnf = normalizer.normalize(type)
      assert_equal [[["::Integer"], ["::String", "::Symbol"]]], dnf.clauses.map {|c| [c.positives.map(&:to_s).sort, c.negatives.map(&:to_s).sort] }
    end
  end

  def test_dnf_equality
    with_sigs do
      assert_equal normalizer.normalize(parse_type("::Integer | ::String")), normalizer.normalize(parse_type("::String | ::Integer"))
      assert_equal normalizer.normalize(parse_type("(::Integer | ::String) & ::Foo")), normalizer.normalize(parse_type("(::Integer & ::Foo) | (::String & ::Foo)"))
    end
  end

  def test_subsumed_clauses_are_pruned
    with_sigs do
      # `A | (A & B)` is `A`
      assert_equal [[["::Integer"], []]], clauses("::Integer | (::Integer & ::Foo)")
      assert_equal [[["::Integer"], []], [["::String"], []]], clauses("(::Integer | ::String) & (::Integer | ::String)")
      # A clause of the same size is kept
      assert_equal [[["::Foo", "::Integer"], []], [["::Foo", "::String"], []]], clauses("(::Integer | ::String) & ::Foo")
    end
  end

  def test_negation_is_pushed_down_before_the_product
    with_sigs do
      literals = (1..30).map(&:to_s).join(" | ")
      union = parse_type(literals)
      # `U & !((U | Integer) & U)`: the negated intersection of unions is read as `!(U | Integer) | !U`, without the
      # DNF of `(U | Integer) & U` being built only to be negated clause by clause
      type = AST::Types::Intersection.build(
        types: [
          union,
          negation(AST::Types::Intersection.build(types: [AST::Types::Union.build(types: [union, parse_type("::Integer")]), union]))
        ]
      )
      assert_predicate normalizer.normalize(type), :bot?

      # `!(U | Integer) | !U` is `!U`, since `!U` subsumes `!(U | Integer)`
      negated = normalizer.normalize(negation(AST::Types::Intersection.build(types: [AST::Types::Union.build(types: [union, parse_type("::Integer")]), union])))
      assert_equal 1, negated.clauses.size
      assert_equal 30, negated.clauses[0].negatives.size
    end
  end

  def test_too_large
    with_sigs do
      literals = (1..70).map(&:to_s).join(" | ")
      type = AST::Types::Intersection.build(types: [parse_type(literals), parse_type(literals.sub("1 |", "1 | 100 |"))])
      assert_raises(SetTheoretic::DNF::TooLarge) { normalizer.normalize(type) }
    end
  end
end
