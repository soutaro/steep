require_relative "../../test_helper"

class NegationTypeTest < Minitest::Test
  include TestHelper
  include FactoryHelper

  include Steep

  Negation = AST::Types::Negation

  def test_build
    with_factory do
      integer = parse_type("::Integer")

      assert_equal Negation.new(type: integer), Negation.build(type: integer)
      assert_equal integer, Negation.build(type: Negation.build(type: integer))
      assert_equal AST::Types::Bot.instance, Negation.build(type: AST::Types::Top.instance)
      assert_equal AST::Types::Top.instance, Negation.build(type: AST::Types::Bot.instance)
    end
  end

  def test_to_s
    with_factory do
      assert_equal "!::Integer", Negation.build(type: parse_type("::Integer")).to_s
      assert_equal "!(::Integer | ::String)", Negation.build(type: parse_type("::Integer | ::String")).to_s
      assert_equal "!(::Integer & ::String)", Negation.build(type: parse_type("::Integer & ::String")).to_s
      assert_equal "!1", Negation.build(type: parse_type("1")).to_s
      assert_equal "!nil", Negation.build(type: parse_type("nil")).to_s
      assert_equal "!(^() -> void)", Negation.build(type: parse_type("^() -> void")).to_s
      assert_equal "::Array[!::Integer]", AST::Builtin::Array.instance_type(Negation.build(type: parse_type("::Integer"))).to_s
    end
  end

  def test_equality_and_hash
    with_factory do
      t1 = Negation.build(type: parse_type("::Integer"))
      t2 = Negation.build(type: parse_type("::Integer"))
      t3 = Negation.build(type: parse_type("::String"))

      assert_equal t1, t2
      assert_equal t1.hash, t2.hash
      refute_equal t1, t3
      assert_equal 1, Set[t1, t2].size
    end
  end

  def test_subst_and_free_variables
    with_factory do
      var = parse_type("T", variables: [:T])
      type = Negation.build(type: var)

      assert_equal Set[:T], type.free_variables

      subst = Interface::Substitution.build([:T], [parse_type("::Integer")])
      assert_equal Negation.build(type: parse_type("::Integer")), type.subst(subst)
      assert_equal Set[], type.subst(subst).free_variables

      same = Negation.build(type: parse_type("::Integer"))
      assert_same same, same.subst(subst)
    end
  end

  def test_children
    with_factory do
      integer = parse_type("::Integer")
      type = Negation.build(type: integer)

      assert_equal [integer], type.each_child.to_a
      assert_equal Negation.build(type: parse_type("::String")), type.map_type { parse_type("::String") }
      assert_equal [0, 0], type.level
    end
  end
end
