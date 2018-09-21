require "test_helper"

class TypeParsingTest < Minitest::Test
  include TestHelper
  include ASTAssertion

  AST = Steep::AST
  Names = Steep::Names

  def test_interface
    type = parse_type("_Foo")
    assert_instance_of AST::Types::Name::Interface, type
    assert_location type, start_line: 1, start_column: 0, end_line: 1, end_column: 4
    assert_equal Names::Interface.new(name: :_Foo, namespace: AST::Namespace.empty), type.name
    assert_equal [], type.args
  end

  def test_interface_qualified
    type = parse_type("::_Foo")
    assert_instance_of AST::Types::Name::Interface, type
    assert_location type, start_line: 1, start_column: 0, end_line: 1, end_column: 6
    assert_equal Names::Interface.new(name: :_Foo, namespace: AST::Namespace.root), type.name
    assert_equal [], type.args
  end

  def test_interface_qualified2
    type = parse_type("Hello::_Foo")
    assert_instance_of AST::Types::Name::Interface, type
    assert_location type, start_line: 1, start_column: 0, end_line: 1, end_column: 11
    assert_equal Names::Interface.new(name: :_Foo, namespace: AST::Namespace.parse("Hello")), type.name
    assert_equal [], type.args
  end

  def test_instance
    type = parse_method_type("() -> Foo").return_type
    assert_instance_of AST::Types::Name::Instance, type
    assert_location type, start_line: 1, start_column: 6, end_line: 1, end_column: 9
    assert_equal Names::Module.new(namespace: AST::Namespace.empty, name: :Foo), type.name
    assert_equal [], type.args
  end

  def test_instance_qualified
    type = parse_type("::Foo")
    assert_instance_of AST::Types::Name::Instance, type
    assert_location type, start_line: 1, start_column: 0, end_line: 1, end_column: 5
    assert_equal Names::Module.new(namespace: AST::Namespace.root, name: :Foo), type.name
    assert_equal [], type.args
  end

  def test_instance_qualified2
    type = parse_type("::Foo::Bar")
    assert_instance_of AST::Types::Name::Instance, type
    assert_location type, start_line: 1, start_column: 0, end_line: 1, end_column: 10
    assert_equal Names::Module.new(namespace: AST::Namespace.parse("::Foo"), name: :Bar), type.name
    assert_equal [], type.args
  end

  def test_class
    type = parse_method_type("() -> Foo.class").return_type

    assert_instance_of AST::Types::Name::Class, type
    assert_location type, start_line: 1, start_column: 6, end_line: 1, end_column: 15
    assert_equal Names::Module.new(namespace: AST::Namespace.empty, name: :Foo),
                 type.name
    assert_nil type.constructor
  end

  def test_module
    type = parse_method_type("() -> Foo.module").return_type

    assert_instance_of AST::Types::Name::Module, type
    assert_location type, start_line: 1, start_column: 6, end_line: 1, end_column: 16
    assert_equal Names::Module.new(namespace: AST::Namespace.empty, name: :Foo),
                 type.name
  end

  def test_module_constructor
    type = parse_method_type("() -> Foo.class constructor").return_type

    assert_instance_of AST::Types::Name::Class, type
    assert_location type, start_line: 1, start_column: 6, end_line: 1, end_column: 27
    assert_equal Names::Module.new(namespace: AST::Namespace.empty, name: :Foo),
                 type.name
    assert type.constructor
  end

  def test_class_noconstructor
    type = parse_method_type("() -> Foo.class noconstructor").return_type

    assert_instance_of AST::Types::Name::Class, type
    assert_location type, start_line: 1, start_column: 6, end_line: 1, end_column: 29
    assert_equal Names::Module.new(namespace: AST::Namespace.empty, name: :Foo),type.name
    refute type.constructor
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

    assert_location type.types.find {|type| type.name == :a},
                    start_line: 1, start_column: 7, end_line: 1, end_column: 9

    assert_location type.types.find {|type| type.name == :b },
                    start_line: 1, start_column: 12, end_line: 1, end_column: 14

    assert_location type.types.find {|type| type.name == :c },
                    start_line: 1, start_column: 17, end_line: 1, end_column: 19
  end

  def test_application
    type = parse_method_type("() -> Array<'a, 'b>").return_type

    assert_instance_of AST::Types::Name::Instance, type
    assert_location type, start_line: 1, start_column: 6, end_line: 1, end_column: 19
    assert_equal Names::Module.new(name: :Array, namespace: AST::Namespace.empty), type.name

    assert_size 2, type.args

    assert_type_var type.args[0], name: :a
    assert_location type.args[0], start_line: 1, start_column: 12, end_line: 1, end_column: 14

    assert_type_var type.args[1], name: :b
    assert_location type.args[1], start_line: 1, start_column: 16, end_line: 1, end_column: 18
  end

  def test_application2
    refute_nil parse_method_type("() -> Array<Array<Integer>>")
  end

  def test_application3
    type = parse_type("Array<::Object>")
    assert_instance_name_type type, name: Names::Module.parse("Array")
    assert_equal 1, type.args.size
    assert_instance_name_type type.args[0], name: Names::Module.parse("::Object")
  end

  def test_self
    type = parse_method_type("() -> self").return_type

    assert_instance_of AST::Types::Self, type
    assert_location type, start_line: 1, start_column: 6, end_line: 1, end_column: 10
  end

  def test_void
    type = parse_method_type("() -> void").return_type

    assert_instance_of AST::Types::Void, type
    assert_equal AST::Types::Void.new, type
    assert_location type, start_line: 1, start_column: 6, end_line: 1, end_column: 10
  end

  def test_optional
    type = parse_method_type("() -> (String | nil)").return_type
    assert_equal AST::Types::Union.build(types: [
      AST::Types::Name.new_instance(name: Names::Module.new(name: :String, namespace: AST::Namespace.empty)),
      AST::Types::Nil.new()
    ]), type
    assert_location type, start_line: 1, start_column: 6, end_line: 1, end_column: 20
  end

  def test_any_or_nil
    type = parse_method_type("() -> (any | nil)").return_type
    assert_equal AST::Types::Union.build(types: [
      AST::Types::Any.new(),
      AST::Types::Nil.new()
    ]), type
    assert_location type, start_line: 1, start_column: 6, end_line: 1, end_column: 17
  end

  def test_any_q
    type = parse_method_type("() -> any?").return_type
    assert_equal AST::Types::Union.build(types: [
      AST::Types::Any.new(),
      AST::Types::Nil.new()
    ]), type
    assert_location type, start_line: 1, start_column: 6, end_line: 1, end_column: 10
  end

  def test_literal_type
    parse_type("1").yield_self do |type|
      assert_equal AST::Types::Literal.new(value: 1), type
      assert_equal AST::Types::Name.new_instance(name: Names::Module.new(name: :Integer, namespace: AST::Namespace.root)),
                   type.back_type
    end

    parse_type('"hello"').yield_self do |type|
      assert_equal AST::Types::Literal.new(value: "hello"), type
      assert_equal AST::Types::Name.new_instance(name: Names::Module.new(name: :String, namespace: AST::Namespace.root)),
                   type.back_type
    end

    parse_type(":foo123").yield_self do |type|
      assert_equal AST::Types::Literal.new(value: :foo123), type
      assert_equal AST::Types::Name.new_instance(name: Names::Module.new(name: :Symbol, namespace: AST::Namespace.root)),
                   type.back_type
    end
  end

  def test_boolean
    parse_type("bool").yield_self do |type|
      assert_equal AST::Types::Boolean.new, type
    end
  end
  
  def test_tuple_type
    parse_type("[1, String]").yield_self do |type|
      assert_equal AST::Types::Tuple.new(types: [parse_type("1"), parse_type("String")]), type
    end

    assert_raises Racc::ParseError do
      parse_type("[]")
    end
  end

  def test_proc_type
    parse_type("^() -> void").yield_self do |type|
      assert_instance_of AST::Types::Proc, type
      assert_equal "^() -> void", type.to_s
    end

    parse_type("^(Integer, ?String, *Symbol) -> void").yield_self do |type|
      assert_instance_of AST::Types::Proc, type
      assert_equal "^(Integer, ?String, *Symbol) -> void", type.to_s
    end
  end

  def test_alias
    parse_type("foo").yield_self do |type|
      assert_instance_of AST::Types::Name::Alias, type
      assert_equal Names::Alias.new(name: :foo, namespace: AST::Namespace.empty), type.name
    end

    parse_type("::foo").yield_self do |type|
      assert_instance_of AST::Types::Name::Alias, type
      assert_equal Names::Alias.new(name: :foo, namespace: AST::Namespace.root), type.name
    end

    parse_type("Foo::foo").yield_self do |type|
      assert_instance_of AST::Types::Name::Alias, type
      assert_equal Names::Alias.new(name: :foo, namespace: AST::Namespace.parse("Foo")), type.name
    end
  end
end
