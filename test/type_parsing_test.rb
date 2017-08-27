require "test_helper"

class TypeParsingTest < Minitest::Test
  include TestHelper

  def test_interface
    type = parse_method_type("() -> _Foo").return_type
    assert_equal Steep::Types::Name.new(name: Steep::TypeName::Interface.new(name: :_Foo), params: []), type
  end

  def test_instance
    type = parse_method_type("() -> Foo").return_type
    assert_equal Steep::Types::Name.new(name: Steep::TypeName::Instance.new(name: :Foo), params: []), type
  end

  def test_class
    type = parse_method_type("() -> Foo.class").return_type
    assert_equal Steep::Types::Name.new(name: Steep::TypeName::Module.new(name: :Foo), params: []), type
  end

  def test_module
    type = parse_method_type("() -> Foo.module").return_type
    assert_equal Steep::Types::Name.new(name: Steep::TypeName::Module.new(name: :Foo), params: []), type
  end

  def test_type_var
    type = parse_method_type("() -> 'a").return_type
    assert_equal Steep::Types::Var.new(name: :a), type
  end

  def test_union
    type = parse_method_type("() -> ('a | 'b | 'c)").return_type
    assert_equal Steep::Types::Union.new(types: [Steep::Types::Var.new(name: :a),
                                                 Steep::Types::Var.new(name: :b),
                                                 Steep::Types::Var.new(name: :c)]), type
  end

  def test_application
    type = parse_method_type("() -> Array<Symbol, 'a>").return_type
    assert_equal Steep::Types::Name.new(name: Steep::TypeName::Instance.new(name: :Array),
                                        params: [
                                          Steep::Types::Name.new(name: Steep::TypeName::Instance.new(name: :Symbol), params: []),
                                          Steep::Types::Var.new(name: :a)
                                        ]), type
  end
end
