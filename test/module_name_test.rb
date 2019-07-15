require_relative "test_helper"

class ModuleNameTest < Minitest::Test
  include TestHelper
  include FactoryHelper

  Namespace = Steep::AST::Namespace
  Names = Steep::Names

  def test_from_const_node
    with_factory do
      assert_equal Names::Module.new(namespace: Namespace.empty, name: :C), Names::Module.from_node(parse_ruby("C").node)
      assert_equal Names::Module.new(namespace: Namespace.root, name: :C), Names::Module.from_node(parse_ruby("::C").node)

      assert_equal Names::Module.new(namespace: Namespace.parse("A::B"), name: :C), Names::Module.from_node(parse_ruby("A::B::C").node)
      assert_equal Names::Module.new(namespace: Namespace.parse("::A::B"), name: :C), Names::Module.from_node(parse_ruby("::A::B::C").node)
      assert_nil Names::Module.from_node(parse_ruby("x").node)
      assert_nil Names::Module.from_node(parse_ruby("A::x::C").node)
    end
  end

  def test_from_casgn_node
    with_factory do
      assert_equal Names::Module.new(namespace: Namespace.empty, name: :C), Names::Module.from_node(parse_ruby("C = 1").node)
      assert_equal Names::Module.new(namespace: Namespace.root, name: :C), Names::Module.from_node(parse_ruby("::C = 2").node)

      assert_equal Names::Module.new(namespace: Namespace.parse("A::B"), name: :C), Names::Module.from_node(parse_ruby("A::B::C = 3").node)
      assert_equal Names::Module.new(namespace: Namespace.parse("::A::B"), name: :C), Names::Module.from_node(parse_ruby("::A::B::C = 4").node)
      assert_nil Names::Module.from_node(parse_ruby("x = 5").node)
      assert_nil Names::Module.from_node(parse_ruby("A::x::C = 6").node)
    end
  end
end
