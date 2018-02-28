require_relative "test_helper"

class ModuleNameTest < Minitest::Test
  include TestHelper

  ModuleName = Steep::ModuleName

  def test_absolute
    assert_operator ModuleName.parse("::Object"), :absolute?
    assert_operator ModuleName.parse("Object"), :relative?
  end

  def test_concat
    assert_equal ModuleName.parse("Object::String"), ModuleName.parse("Object") + ModuleName.parse("String")
    assert_equal ModuleName.parse("Object::String"), ModuleName.parse("Object") + "String"
    assert_equal ModuleName.parse("::String"), ModuleName.parse("Object") + "::String"
  end

  def test_components
    assert_equal [ModuleName.parse("Object"), ModuleName.parse("String")], ModuleName.parse("Object::String").components
    assert_equal [ModuleName.parse("::Object"), ModuleName.parse("String")], ModuleName.parse("::Object::String").components
  end

  def test_parent
    assert_equal ModuleName.parse("::Object"), ModuleName.parse("::Object::String").parent
    assert_equal ModuleName.parse("Object"), ModuleName.parse("Object::String").parent
    assert_nil ModuleName.parse("::Object").parent
  end

  def test_from_node
    assert_equal ModuleName.parse("A::B::C"), ModuleName.from_node(parse_ruby("A::B::C").node)
    assert_equal ModuleName.parse("::A::B::C"), ModuleName.from_node(parse_ruby("::A::B::C").node)
    assert_nil ModuleName.from_node(parse_ruby("x").node)
    assert_nil ModuleName.from_node(parse_ruby("A::x::C").node)
  end
end
