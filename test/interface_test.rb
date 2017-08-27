require "test_helper"

class InterfaceTest < Minitest::Test
  Interface = Steep::Interface

  include TestHelper

  def test_closed
    # closed? is not about type variables, but about instance/class/module types.

    assert_operator Interface.new(name: :_X, methods: {}), :closed?
    assert_operator Interface.new(name: :_X, methods: { foo: parse_single_method("(String) -> any") }), :closed?
    assert_operator Interface.new(name: :_X, methods: { foo: parse_single_method("<'a> ('a, ?_Some, *_y, x: Foo, ?y: Bar, **'b) { (Integer | String) -> any } -> String") }), :closed?
    refute_operator Interface.new(name: :_X, methods: { foo: parse_single_method("(instance) -> any") }), :closed?
    refute_operator Interface.new(name: :_X, methods: { foo: parse_single_method("(class) -> any") }), :closed?
    refute_operator Interface.new(name: :_X, methods: { foo: parse_single_method("(module) -> any") }), :closed?
  end
end
