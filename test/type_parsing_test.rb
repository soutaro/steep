require "test_helper"

class TypeParsingTest < Minitest::Test
  include TestHelper

  def parse_method(string)
    Steep::Parser.parse_method(string)
  end

  def test_interface
    type = parse_method("() -> _Foo").return_type
    assert_equal Steep::Types::Name.new(name: Steep::TypeName::Interface.new(name: :_Foo), params: []), type
  end

  def test_instance
    type = parse_method("() -> Foo").return_type
    assert_equal Steep::Types::Name.new(name: Steep::TypeName::Instance.new(name: :Foo), params: []), type
  end

  def test_class
    type = parse_method("() -> Foo.class").return_type
    assert_equal Steep::Types::Name.new(name: Steep::TypeName::Module.new(name: :Foo), params: []), type
  end

  def test_module
    type = parse_method("() -> Foo.module").return_type
    assert_equal Steep::Types::Name.new(name: Steep::TypeName::Module.new(name: :Foo), params: []), type
  end

  def test_type_var
    type = parse_method("() -> 'a").return_type
    assert_equal Steep::Types::Var.new(name: :a), type
  end

  def test_union
    type = parse_method("() -> 'a | 'b").return_type
    assert_equal Steep::Types::Union.new(types: [Steep::Types::Var.new(name: :a), Steep::Types::Var.new(name: :b)]), type
  end

  def test_application
    type = parse_method("() -> Array<Symbol, 'a>").return_type
    assert_equal Steep::Types::Name.new(name: Steep::TypeName::Instance.new(name: :Array),
                                        params: [
                                          Steep::Types::Name.new(name: Steep::TypeName::Instance.new(name: :Symbol), params: []),
                                          Steep::Types::Var.new(name: :a)
                                        ]), type
  end
end
