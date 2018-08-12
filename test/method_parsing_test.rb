require "test_helper"

class MethodParsingTest < Minitest::Test
  include ASTAssertion

  T = Steep::AST::Types
  Interface = Steep::Interface
  ModuleName = Steep::ModuleName

  def test_no_params1
    method = Steep::Parser.parse_method("() -> any")
    assert_location method, start_line: 1, start_column: 0, end_line: 1, end_column: 9
    assert_nil method.type_params
    assert_nil method.params
    assert_nil method.block
    assert_any_type method.return_type
    assert_location method.return_type, start_line: 1, start_column: 6, end_line: 1, end_column: 9
  end

  def test_no_params2
    method = Steep::Parser.parse_method("-> any")
    assert_location method, start_line: 1, start_column: 0, end_line: 1, end_column: 6
    assert_nil method.type_params
    assert_nil method.params
    assert_nil method.block
    assert_any_type method.return_type
  end

  def test_required_params
    method = Steep::Parser.parse_method("(any, String) -> any")
    assert_location method, start_line: 1, start_column: 0, end_line: 1, end_column: 20

    assert_params_length method.params, 2
    assert_required_param method.params, index: 0 do |type, params|
      assert_any_type type
      assert_location type, start_line: 1, start_column: 1, end_line: 1, end_column: 4
      assert_location params, start_line: 1, start_column: 1, end_line: 1, end_column: 4
    end
    assert_required_param method.params, index: 1 do |type, params|
      assert_instance_name_type type, name: ModuleName.parse(:String)
      assert_location type, start_line: 1, start_column: 6, end_line: 1, end_column: 12
      assert_location params, start_line: 1, start_column: 6, end_line: 1, end_column: 12
    end

    assert_nil method.block

    assert_any_type method.return_type
  end

  def test_optional_params
    method = Steep::Parser.parse_method("(?String, ?any) -> any")
    assert_location method, start_line: 1, start_column: 0, end_line: 1, end_column: 22

    assert_params_length method.params, 2
    assert_optional_param method.params, index: 0 do |type, params|
      assert_instance_name_type type, name: ModuleName.parse("String")
      assert_location type, start_line: 1, start_column: 2, end_line: 1, end_column: 8
      assert_location params, start_line: 1, start_column: 1, end_line: 1, end_column: 8
    end
    assert_optional_param method.params, index: 1 do |type, params|
      assert_any_type type
      assert_location type, start_line: 1, start_column: 11, end_line: 1, end_column: 14
      assert_location params, start_line: 1, start_column: 10, end_line: 1, end_column: 14
    end

    assert_nil method.block

    assert_any_type method.return_type
  end

  def test_rest_param
    method = Steep::Parser.parse_method("(*Integer) -> any")
    assert_location method, start_line: 1, start_column: 0, end_line: 1, end_column: 17

    assert_params_length method.params, 1
    assert_rest_param method.params, index: 0 do |type, params|
      assert_instance_name_type type, name: ModuleName.parse(:Integer)
      assert_location type, start_line: 1, start_column: 2, end_line: 1, end_column: 9
      assert_location params, start_line: 1, start_column: 1, end_line: 1, end_column: 9
    end

    assert_nil method.block

    assert_any_type method.return_type
  end

  def test_required_keywords
    method = Steep::Parser.parse_method("(name: String, email: any) -> any")
    assert_location method, start_line: 1, start_column: 0, end_line: 1, end_column: 33

    assert_params_length method.params, 2
    assert_required_keyword method.params, index: 0, name: :name do |type, params|
      assert_instance_name_type type, name: ModuleName.parse("String")
      assert_location type, start_line: 1, start_column: 7, end_line: 1, end_column: 13
      assert_location params, start_line: 1, start_column: 1, end_line: 1, end_column: 13
    end
    assert_required_keyword method.params, index: 1, name: :email do |type, params|
      assert_any_type type
      assert_location type, start_line: 1, start_column: 22, end_line: 1, end_column: 25
      assert_location params, start_line: 1, start_column: 15, end_line: 1, end_column: 25
    end

    assert_nil method.block
    assert_any_type method.return_type
  end

  def test_optional_keywords
    method = Steep::Parser.parse_method("(?name: String, ?email: any) -> any")
    assert_location method, start_line: 1, start_column: 0, end_line: 1, end_column: 35

    assert_params_length method.params, 2
    assert_optional_keyword method.params, index: 0, name: :name do |type, params|
      assert_instance_name_type type, name: ModuleName.parse("String")
      assert_location type, start_line: 1, start_column: 8, end_line: 1, end_column: 14
      assert_location params, start_line: 1, start_column: 1, end_line: 1, end_column: 14
    end
    assert_optional_keyword method.params, index: 1, name: :email do |type, params|
      assert_any_type type
      assert_location type, start_line: 1, start_column: 24, end_line: 1, end_column: 27
      assert_location params, start_line: 1, start_column: 16, end_line: 1, end_column: 27
    end

    assert_nil method.block
    assert_any_type method.return_type
  end

  def test_rest_keyword
    method = Steep::Parser.parse_method("(**Integer) -> any")
    assert_location method, start_line: 1, start_column: 0, end_line: 1, end_column: 18

    assert_params_length method.params, 1
    assert_rest_keyword method.params, index: 0 do |type, params|
      assert_instance_name_type type, name: ModuleName.parse("Integer")
      assert_location type, start_line: 1, start_column: 3, end_line: 1, end_column: 10
      assert_location params, start_line: 1, start_column: 1, end_line: 1, end_column: 10
    end

    assert_nil method.block
    assert_any_type method.return_type
  end

  def test_params
    method = Steep::Parser.parse_method("(T0, ?T1, *T2, name: T3, ?email: T4, **T5) -> any")
    assert_location method, start_line: 1, start_column: 0, end_line: 1, end_column: 49

    assert_params_length method.params, 6
    assert_required_param method.params, index: 0 do |type, params|
      assert_instance_of T::Name::Instance, type
      assert_equal :T0, type.name.name
      assert_location type, start_line: 1, start_column: 1, end_line: 1, end_column: 3
      assert_location params, start_line: 1, start_column: 1, end_line: 1, end_column: 3
    end
    assert_optional_param method.params, index: 1 do |type, params|
      assert_instance_of T::Name::Instance, type
      assert_equal :T1, type.name.name
      assert_location type, start_line: 1, start_column: 6, end_line: 1, end_column: 8
      assert_location params, start_line: 1, start_column: 5, end_line: 1, end_column: 8
    end
    assert_rest_param method.params, index: 2 do |type, params|
      assert_instance_of T::Name::Instance, type
      assert_equal :T2, type.name.name
      assert_location type, start_line: 1, start_column: 11, end_line: 1, end_column: 13
      assert_location params, start_line: 1, start_column: 10, end_line: 1, end_column: 13
    end
    assert_required_keyword method.params, index: 3, name: :name do |type, params|
      assert_instance_of T::Name::Instance, type
      assert_equal :T3, type.name.name
      assert_location type, start_line: 1, start_column: 21, end_line: 1, end_column: 23
      assert_location params, start_line: 1, start_column: 15, end_line: 1, end_column: 23
    end
    assert_optional_keyword method.params, index: 4, name: :email do |type, params|
      assert_instance_of T::Name::Instance, type
      assert_equal :T4, type.name.name
      assert_location type, start_line: 1, start_column: 33, end_line: 1, end_column: 35
      assert_location params, start_line: 1, start_column: 25, end_line: 1, end_column: 35
    end
    assert_rest_keyword method.params, index: 5 do |type, params|
      assert_instance_of T::Name::Instance, type
      assert_equal :T5, type.name.name
      assert_location type, start_line: 1, start_column: 39, end_line: 1, end_column: 41
      assert_location params, start_line: 1, start_column: 37, end_line: 1, end_column: 41
    end

    assert_nil method.block
    assert_any_type method.return_type
  end

  def test_block
    method = Steep::Parser.parse_method("() { (*Integer) -> String } -> any")
    assert_location method, start_line: 1, start_column: 0, end_line: 1, end_column: 34

    assert_instance_of Steep::AST::MethodType::Block, method.block
    assert_location method.block, start_line: 1, start_column: 3, end_line: 1, end_column: 27

    assert_params_length method.block.params, 1
    assert_rest_param method.block.params, index: 0 do |type, params|
      assert_instance_name_type type, name: ModuleName.parse(:Integer)
      assert_location type, start_line: 1, start_column: 7, end_line: 1, end_column: 14
      assert_location params, start_line: 1, start_column: 6, end_line: 1, end_column: 14
    end

    assert_instance_name_type method.block.return_type, name: ModuleName.parse(:String)
    assert_location method.block.return_type, start_line: 1, start_column: 19, end_line: 1, end_column: 25

    assert_any_type method.return_type
  end

  def test_empty_block
    method = Steep::Parser.parse_method("{ } -> any")
    assert_location method, start_line: 1, start_column: 0, end_line: 1, end_column: 10

    assert_instance_of Steep::AST::MethodType::Block, method.block
    assert_location method.block, start_line: 1, start_column: 0, end_line: 1, end_column: 3

    assert_nil method.block.params
    assert_nil method.block.return_type

    assert_any_type method.return_type
  end

  def test_parameterized
    method = Steep::Parser.parse_method("<'a, 'b> () -> String")
    assert_location method, start_line: 1, start_column: 0, end_line: 1, end_column: 21

    assert_type_params method.type_params, variables: [:a, :b]
    assert_location method.type_params, start_line: 1, start_column: 0, end_line: 1, end_column: 8
  end

  def test_var_type
    method = Steep::Parser.parse_method("'a -> 'b")
    assert_location method, start_line: 1, start_column: 0, end_line: 1, end_column: 8

    assert_params_length method.params, 1
    assert_required_param method.params, index: 0 do |type, params|
      assert_type_var type, name: :a
      assert_location params, start_line: 1, start_column: 0, end_line: 1, end_column: 2
    end

    assert_type_var method.return_type, name: :b
    assert_location method.return_type, start_line: 1, start_column: 6, end_line: 1, end_column: 8
  end

  def test_self_and_class_and_module
    method = Steep::Parser.parse_method("(class, module) -> instance")
    assert_location method, start_column: 0, end_column: 27

    assert_params_length method.params, 2
    assert_required_param method.params, index: 0 do |type, params|
      assert_instance_of Steep::AST::Types::Class, type
      assert_location type, start_column: 1, end_column: 6
      assert_location params, start_column: 1, end_column: 6
    end
    assert_required_param method.params, index: 1 do |type, params|
      assert_instance_of Steep::AST::Types::Class, type
      assert_location type, start_column: 8, end_column: 14
      assert_location params, start_column: 8, end_column: 14
    end

    assert_instance_of Steep::AST::Types::Instance, method.return_type
    assert_location method.return_type, start_column: 19, end_column: 27
  end


  def test_union
    method = Steep::Parser.parse_method("('a | 'b, ?'c|'d)-> Array<'a | 'b>")
    assert_location method, start_column: 0, end_column: 34

    assert_params_length method.params, 2

    assert_required_param method.params, index: 0 do |type, params|
      assert_union_type type do |types|
        t1 = types.find {|type| type.name == :a }
        t2 = types.find {|type| type.name == :b }

        assert_location t1, start_column: 1, end_column: 3
        assert_location t2, start_column: 6, end_column: 8
      end
      assert_location type, start_column: 1, end_column: 8
      assert_location params, start_column: 1, end_column: 8
    end

    assert_optional_param method.params, index: 1 do |type, params|
      assert_union_type type do |types|
        c = types.find {|type| type.name == :c }
        d = types.find {|type| type.name == :d }

        assert_type_var c, name: :c
        assert_location c, start_column: 11, end_column: 13
        assert_type_var d, name: :d
        assert_location d, start_column: 14, end_column: 16
      end
      assert_location type, start_column: 11, end_column: 16
      assert_location params, start_column: 10, end_column: 16
    end

    assert_instance_name_type method.return_type, name: ModuleName.parse(:Array) do |(type)|
      assert_union_type type do |types|
        a = types.find {|type| type.name == :a }
        b = types.find {|type| type.name == :b }

        assert_type_var a, name: :a
        assert_location a, start_column: 26, end_column: 28
        assert_type_var b, name: :b
        assert_location b, start_column: 31, end_column: 33
      end
      assert_location type, start_column: 26, end_column: 33
    end
    assert_location method.return_type, start_column: 20, end_column: 34
  end
end
