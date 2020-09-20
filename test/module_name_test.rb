require_relative "test_helper"

class ModuleHelperTest < Minitest::Test
  include TestHelper
  include FactoryHelper

  Namespace = RBS::Namespace

  include Steep::ModuleHelper

  def test_from_const_node
    with_factory do
      assert_equal TypeName("C"), module_name_from_node(parse_ruby("C").node)
      assert_equal TypeName("::C"), module_name_from_node(parse_ruby("::C").node)

      assert_equal TypeName("A::B::C"), module_name_from_node(parse_ruby("A::B::C").node)
      assert_equal TypeName("::A::B::C"), module_name_from_node(parse_ruby("::A::B::C").node)
      assert_nil module_name_from_node(parse_ruby("x").node)
      assert_nil module_name_from_node(parse_ruby("A::x::C").node)
    end
  end

  def test_from_casgn_node
    with_factory do
      assert_equal TypeName("C"), module_name_from_node(parse_ruby("C = 1").node)
      assert_equal TypeName("::C"), module_name_from_node(parse_ruby("::C = 2").node)

      assert_equal TypeName("A::B::C"), module_name_from_node(parse_ruby("A::B::C = 3").node)
      assert_equal TypeName("::A::B::C"), module_name_from_node(parse_ruby("::A::B::C = 4").node)
      assert_nil module_name_from_node(parse_ruby("x = 5").node)
      assert_nil module_name_from_node(parse_ruby("A::x::C = 6").node)
    end
  end
end
