require "test_helper"

class TypeAssignabilityTest < Minitest::Test
  T = Steep::Types

  def test_1
    assignability = Steep::TypeAssignability.new

    assert assignability.test(src: T::Any.new, dest: T::Any.new)
  end

  def test_if1
    if1 = T::Interface.new(name: :Foo, methods: {})
    if2 = T::Interface.new(name: :Foo, methods: {})

    assignability = Steep::TypeAssignability.new
    assignability.add_interface if1
    assignability.add_interface if2

    assert assignability.test(src: if1, dest: if2)
  end

  def test_if2
    if1 = T::Interface.new(name: :Foo, methods: { foo: T::Interface::Method.new(param_types: [], block: nil, return_type: T::Any.new) })
    if2 = T::Interface.new(name: :Bar, methods: { foo: T::Interface::Method.new(param_types: [], block: nil, return_type: T::Any.new) })

    assignability = Steep::TypeAssignability.new
    assignability.add_interface if1
    assignability.add_interface if2

    assert assignability.test(src: if1, dest: if2)
  end
end
