require_relative "test_helper"

class ModuleHelperTest < Minitest::Test
  include TestHelper
  include FactoryHelper

  Namespace = RBS::Namespace

  include Steep::ModuleHelper

  def test_from_const_node
    with_factory do
      parse_ruby("C").node.tap do |node|
        assert_equal RBS::TypeName.parse("C"), module_name_from_node(node.children[0], node.children[1])
      end
      parse_ruby("::C").node.tap do |node|
        assert_equal RBS::TypeName.parse("::C"), module_name_from_node(node.children[0], node.children[1])
      end
      parse_ruby("A::B::C").node.tap do |node|
        assert_equal RBS::TypeName.parse("A::B::C"), module_name_from_node(node.children[0], node.children[1])
      end
    end
  end
end
