require_relative "test_helper"

class InterfaceTest < Minitest::Test
  include TestHelper
  include FactoryHelper

  def test_method_type_params_union
    with_factory do |factory|
      assert_equal parse_method_type("(String | Integer) -> any").params,
                   parse_method_type("(String) -> any").params | parse_method_type("(Integer) -> any").params

      assert_equal parse_method_type("(?String | Integer) -> any").params,
                   parse_method_type("(?String) -> any").params | parse_method_type("(Integer) -> any").params

      assert_equal parse_method_type("(?String) -> any").params,
                   parse_method_type("(String) -> any").params | parse_method_type("() -> any").params

      assert_equal parse_method_type("(?String | Symbol, *Symbol) -> any").params,
                   parse_method_type("(String) -> any").params | parse_method_type("(*Symbol) -> any").params

      assert_equal parse_method_type("(?String | Symbol, *Symbol) -> void").params,
                   parse_method_type("(String) -> params").params | parse_method_type("(*Symbol) -> void").params

      assert_equal parse_method_type("(name: String | Symbol, ?email: String | Array, ?age: Integer | Object, **Array | Object) -> void").params,
                   parse_method_type("(name: String, email: String, **Object) -> void").params | parse_method_type("(name: Symbol, age: Integer, **Array) -> void").params

      assert_equal parse_method_type("() ?{ (String | Integer) -> (Array | Hash) } -> void").params,
                   parse_method_type("() ?{ (String) -> Array } -> void").params | parse_method_type("() { (Integer) -> Hash } -> void").params
    end
  end

  def test_method_type_params_intersection
    with_factory do |factory|
      assert_equal parse_method_type("(String & Integer) -> any").params,
                   parse_method_type("(String) -> any").params & parse_method_type("(Integer) -> any").params

      assert_equal parse_method_type("(String & Integer) -> any").params,
                   parse_method_type("(?String) -> any").params & parse_method_type("(Integer) -> any").params

      assert_equal parse_method_type("(String & Integer) -> any").params,
                   parse_method_type("(String) -> any").params & parse_method_type("(*Integer) -> any").params

      assert_equal parse_method_type("(bot) -> any").params,
                   (parse_method_type("(String) -> any").params & parse_method_type("() -> any").params)

      assert_equal parse_method_type("() -> any").params,
                   parse_method_type("(?String) -> any").params & parse_method_type("() -> any").params

      assert_equal parse_method_type("(String & Symbol) -> any").params,
                   parse_method_type("(String) -> any").params & parse_method_type("(*Symbol) -> any").params

      assert_equal parse_method_type("(?String & Integer) -> any").params,
                   parse_method_type("(?String) -> any").params & parse_method_type("(?Integer) -> any").params

      assert_equal parse_method_type("(String & Symbol) -> void").params,
                   parse_method_type("(String) -> params").params & parse_method_type("(*Symbol) -> void").params

      assert_equal parse_method_type("(name: String & Symbol, email: String & Array, age: Integer & Object, **Array & Object) -> void").params,
                   (parse_method_type("(name: String, email: String, **Object) -> void").params & parse_method_type("(name: Symbol, age: Integer, **Array) -> void").params)
    end
  end

  def test_method_type_plus
    with_factory do |factory|
      assert_equal parse_method_type("(String | Integer) -> any"),
                   parse_method_type("(String) -> any") + parse_method_type("(Integer) -> any")

      assert_equal parse_method_type("(?String | Integer) -> any"),
                   parse_method_type("(?String) -> any") + parse_method_type("(Integer) -> any")

      assert_equal parse_method_type("(?String) -> any"),
                   parse_method_type("(String) -> any") + parse_method_type("() -> any")

      assert_equal parse_method_type("(?String | Symbol, *Symbol) -> any"),
                   parse_method_type("(String) -> any") + parse_method_type("(*Symbol) -> any")

      assert_equal parse_method_type("(?String | Symbol, *Symbol) -> (Array | Hash)"),
                   parse_method_type("(String) -> Hash") + parse_method_type("(*Symbol) -> Array")

      assert_equal parse_method_type("(name: String | Symbol, ?email: String | Array, ?age: Integer | Object, **Array | Object) -> void"),
                   parse_method_type("(name: String, email: String, **Object) -> void") + parse_method_type("(name: Symbol, age: Integer, **Array) -> void")

      assert_equal parse_method_type("() ?{ (String | Integer) -> (Array | Hash) } -> void"),
                   parse_method_type("() ?{ (String) -> Array } -> void") + parse_method_type("() { (Integer) -> Hash } -> void")
    end
  end

  def test_method_type_params_poly
    skip "Skip testing MethodType#+ for polymorphic types, which requires equality modulo universal quantifiers"
    with_factory do |factory|
      assert_equal parse_method_type("[A] () ?{ (String) -> A } -> (String | A)").to_s,
                   (parse_method_type("() -> String") + parse_method_type("[A] { (String) -> A } -> A")).to_s
    end
  end
end
