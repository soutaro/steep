require "test_helper"

class TypeParsingTest < Minitest::Test
  include TestHelper
  include ASTAssertion

  AST = Steep::AST

  def test_interface
    type = parse_method_type("() -> _Foo").return_type
    assert_instance_of AST::Types::Name, type
    assert_location type, start_line: 1, start_column: 6, end_line: 1, end_column: 10
    assert_equal :_Foo, type.name
    assert_equal :interface, type.kind
    assert_equal [], type.args
    assert_equal [], type.attributes
  end

  def test_instance
    type = parse_method_type("() -> Foo").return_type
    assert_instance_of AST::Types::Name, type
    assert_location type, start_line: 1, start_column: 6, end_line: 1, end_column: 9
    assert_equal :Foo, type.name
    assert_equal :instance, type.kind
    assert_equal [], type.args
    assert_equal [], type.attributes
  end

  def test_class
    type = parse_method_type("() -> Foo.class").return_type

    assert_instance_of AST::Types::Name, type
    assert_location type, start_line: 1, start_column: 6, end_line: 1, end_column: 15
    assert_equal :Foo, type.name
    assert_equal :class, type.kind
    assert_equal [], type.args
    assert_equal [], type.attributes
  end

  def test_module
    type = parse_method_type("() -> Foo.module").return_type

    assert_instance_of AST::Types::Name, type
    assert_location type, start_line: 1, start_column: 6, end_line: 1, end_column: 16
    assert_equal :Foo, type.name
    assert_equal :module, type.kind
    assert_equal [], type.args
    assert_equal [], type.attributes
  end

  def test_module_constructor
    type = parse_method_type("() -> Foo.class constructor").return_type

    assert_instance_of AST::Types::Name, type
    assert_location type, start_line: 1, start_column: 6, end_line: 1, end_column: 27
    assert_equal :Foo, type.name
    assert_equal :class, type.kind
    assert_equal [], type.args
    assert_equal [:constructor], type.attributes
  end

  def test_class_noconstructor
    type = parse_method_type("() -> Foo.class noconstructor").return_type

    assert_instance_of AST::Types::Name, type
    assert_location type, start_line: 1, start_column: 6, end_line: 1, end_column: 29
    assert_equal :Foo, type.name
    assert_equal :class, type.kind
    assert_equal [], type.args
    assert_equal [:noconstructor], type.attributes
  end

  def test_type_var
    type = parse_method_type("() -> 'a").return_type

    assert_type_var type, name: :a
    assert_location type, start_line: 1, start_column: 6, end_line: 1, end_column: 8
  end

  def test_union
    type = parse_method_type("() -> ('a | 'b | 'c)").return_type

    assert_instance_of AST::Types::Union, type
    assert_location type, start_line: 1, start_column: 6, end_line: 1, end_column: 20
    assert_size 3, type.types

    a, b, c = type.types

    assert_type_var a, name: :a
    assert_location a, start_line: 1, start_column: 7, end_line: 1, end_column: 9

    assert_type_var b, name: :b
    assert_location b, start_line: 1, start_column: 12, end_line: 1, end_column: 14

    assert_type_var c, name: :c
    assert_location c, start_line: 1, start_column: 17, end_line: 1, end_column: 19
  end

  def test_application
    type = parse_method_type("() -> Array<'a, 'b>").return_type

    assert_instance_of AST::Types::Name, type
    assert_location type, start_line: 1, start_column: 6, end_line: 1, end_column: 19
    assert_equal :Array, type.name
    assert_equal :instance, type.kind
    assert_empty type.attributes
    assert_size 2, type.args

    assert_type_var type.args[0], name: :a
    assert_location type.args[0], start_line: 1, start_column: 12, end_line: 1, end_column: 14

    assert_type_var type.args[1], name: :b
    assert_location type.args[1], start_line: 1, start_column: 16, end_line: 1, end_column: 18
  end

  def test_application2
    refute_nil parse_method_type("() -> Array<Array<Integer>>")
  end
end
