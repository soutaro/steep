require_relative "test_helper"

class TypeTest < Minitest::Test
  Types = Steep::AST::Types

  def test_level
    assert_equal [0], Types::Var.new(name: :foo).level
    assert_equal [0, 0], Types::Intersection.build(types: [Types::Var.new(name: :foo)]).level
    assert_equal [1], Types::Any.new.level
    assert_equal [0, 0], Types::Name.new_instance(name: :"String", args: [Types::Var.new(name: :foo)]).level
    assert_equal [0, 1], Types::Name.new_instance(name: :"String", args: [Types::Any.new]).level
    assert_equal [0, 2], Types::Name.new_instance(name: :"String", args: [Types::Any.new, Types::Any.new]).level
    assert_equal [0, 0, 1], Types::Union.build(types: [Types::Name.new_instance(name: :"String", args: [Types::Any.new])]).level
  end
end
