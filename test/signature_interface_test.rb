require "test_helper"

class SignatureInterfaceTest < Minitest::Test
  include TestHelper

  Types = Steep::Types

  def test_to_interface
    interface, _ = parse_signature(<<-EOF)
interface _foo<'a>
  def set: ('a) -> instance
  def get: () -> 'a 
  def map: <'b> () { ('a) -> 'b } -> _foo<'b>
end
    EOF

    interface_ = interface.to_interface(klass: Types::Name.interface(name: :_class),
                                        instance: Types::Name.interface(name: :_instance),
                                        params: [Types::Name.interface(name: :_Numeric)])

    assert_instance_of Steep::Interface, interface_

    assert_equal parse_single_method("(_Numeric) -> _instance"), interface_.methods[:set]
    assert_equal parse_single_method("() -> _Numeric"), interface_.methods[:get]
    assert_equal parse_single_method("<'b> () { (_Numeric) -> 'b } -> _foo<'b>"), interface_.methods[:map]
  end

  def test_to_interface_failure
    interface, _ = parse_signature(<<-EOF)
interface _foo<'a>
end
    EOF

    assert_raises RuntimeError do
      interface.to_interface(klass: Types::Name.interface(name: :_class),
                             instance: Types::Name.interface(name: :_instance),
                             params: [])
    end
  end
end
