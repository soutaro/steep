require_relative "test_helper"

class ModuleNameTest < Minitest::Test
  include TestHelper

  Namespace = Steep::AST::Namespace
  ModuleName = Steep::ModuleName

  def test_from_const_node
    assert_equal ModuleName.new(namespace: Namespace.empty, name: :C), ModuleName.from_node(parse_ruby("C").node)
    assert_equal ModuleName.new(namespace: Namespace.root, name: :C), ModuleName.from_node(parse_ruby("::C").node)

    assert_equal ModuleName.new(namespace: Namespace.parse("A::B"), name: :C), ModuleName.from_node(parse_ruby("A::B::C").node)
    assert_equal ModuleName.new(namespace: Namespace.parse("::A::B"), name: :C), ModuleName.from_node(parse_ruby("::A::B::C").node)
    assert_nil ModuleName.from_node(parse_ruby("x").node)
    assert_nil ModuleName.from_node(parse_ruby("A::x::C").node)
  end

  def test_from_casgn_node
    assert_equal ModuleName.new(namespace: Namespace.empty, name: :C), ModuleName.from_node(parse_ruby("C = 1").node)
    assert_equal ModuleName.new(namespace: Namespace.root, name: :C), ModuleName.from_node(parse_ruby("::C = 2").node)

    assert_equal ModuleName.new(namespace: Namespace.parse("A::B"), name: :C), ModuleName.from_node(parse_ruby("A::B::C = 3").node)
    assert_equal ModuleName.new(namespace: Namespace.parse("::A::B"), name: :C), ModuleName.from_node(parse_ruby("::A::B::C = 4").node)
    assert_nil ModuleName.from_node(parse_ruby("x = 5").node)
    assert_nil ModuleName.from_node(parse_ruby("A::x::C = 6").node)
  end
end
