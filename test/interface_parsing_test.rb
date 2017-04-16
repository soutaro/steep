require "test_helper"

class InterfaceParsingTest < Minitest::Test
  T = Steep::Types

  def test_1
    interfaces = Steep::Parser.parse_interfaces(<<-EOF)
interface Foo
  def hello: -> any
  def +: (String) -> Bar
  def interface: -> Symbol   # Some comment
end
    EOF

    assert_equal 1, interfaces.size

    interface = interfaces[0]
    assert_equal :Foo, interface.name
    assert_equal [], interface.params
    assert_equal Steep::Parser.parse_method("-> any"), interface.methods[:hello]
    assert_equal Steep::Parser.parse_method("(String) -> Bar"), interface.methods[:+]
    assert_equal Steep::Parser.parse_method("-> Symbol"), interface.methods[:interface]
  end

  def test_interface_param
    interfaces = Steep::Parser.parse_interfaces(<<-EOF)
interface Foo<'a, 'b>
end
    EOF

    assert_equal 1, interfaces.size

    interface = interfaces[0]
    assert_equal :Foo, interface.name
    assert_equal [:a, :b], interface.params
  end

  def test_method_param
    interfaces = Steep::Parser.parse_interfaces(<<-EOF)
interface Foo
  def foo: <'a> () -> 'a
end
    EOF

    assert_equal 1, interfaces.size

    interface = interfaces[0]
    assert_equal :Foo, interface.name
    assert_equal [], interface.params
    assert_equal Steep::Parser.parse_method("<'a> () -> 'a"), interface.methods[:foo]
  end
end
