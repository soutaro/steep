require_relative "test_helper"

class InterfaceTest < Minitest::Test
  include TestHelper
  include FactoryHelper

  def test_method_type_params_plus
    with_factory do
      assert_equal parse_method_type("(String | Integer) -> untyped").params,
                   parse_method_type("(String) -> untyped").params + parse_method_type("(Integer) -> untyped").params

      assert_equal parse_method_type("(?String | Integer) -> untyped").params,
                   parse_method_type("(?String) -> untyped").params + parse_method_type("(Integer) -> untyped").params

      assert_equal parse_method_type("(?String) -> untyped").params,
                   parse_method_type("(String) -> untyped").params + parse_method_type("() -> untyped").params

      assert_equal parse_method_type("(?String | Symbol, *Symbol) -> untyped").params,
                   parse_method_type("(String) -> untyped").params + parse_method_type("(*Symbol) -> untyped").params

      assert_equal parse_method_type("(?String | Symbol, *Symbol) -> void").params,
                   parse_method_type("(String) -> params").params + parse_method_type("(*Symbol) -> void").params

      assert_equal parse_method_type("(name: String | Symbol, ?email: String | Array, ?age: Integer | Object, **Array | Object) -> void").params,
                   parse_method_type("(name: String, email: String, **Object) -> void").params + parse_method_type("(name: Symbol, age: Integer, **Array) -> void").params

      assert_equal parse_method_type("() ?{ (String | Integer) -> (Array | Hash) } -> void").params,
                   parse_method_type("() ?{ (String) -> Array } -> void").params + parse_method_type("() { (Integer) -> Hash } -> void").params
    end
  end

  def test_method_type_params_intersection
    with_factory do
      # req, none, opt, rest

      # required:required
      assert_equal parse_method_type("(String & Integer) -> untyped").params,
                   parse_method_type("(String) -> untyped").params & parse_method_type("(Integer) -> untyped").params

      # required:none
      assert_nil parse_method_type("(String) -> untyped").params & parse_method_type("() -> untyped").params

      # required:optional
      assert_equal parse_method_type("(String & Integer) -> untyped").params,
                   parse_method_type("(String) -> untyped").params & parse_method_type("(?Integer) -> untyped").params

      # required:rest
      assert_equal parse_method_type("(String & Integer) -> untyped").params,
                   parse_method_type("(String) -> untyped").params & parse_method_type("(*Integer) -> untyped").params

      # none:required
      assert_nil parse_method_type("() -> untyped").params & parse_method_type("(String) -> void").params

      # none:optional
      assert_equal parse_method_type("() -> untyped").params,
                   parse_method_type("() -> untyped").params & parse_method_type("(?Integer) -> untyped").params

      # none:rest
      assert_equal parse_method_type("() -> untyped").params,
                   parse_method_type("() -> untyped").params & parse_method_type("(*Integer) -> untyped").params

      # opt:required
      assert_equal parse_method_type("(String & Integer) -> untyped").params,
                   parse_method_type("(?String) -> untyped").params & parse_method_type("(Integer) -> untyped").params

      # opt:none
      assert_equal parse_method_type("() -> untyped").params,
                   parse_method_type("(?String) -> untyped").params & parse_method_type("() -> untyped").params

      # opt:opt
      assert_equal parse_method_type("(?String & Integer) -> untyped").params,
                   parse_method_type("(?String) -> untyped").params & parse_method_type("(?Integer) -> untyped").params

      # opt:rest
      assert_equal parse_method_type("(?String & Integer) -> untyped").params,
                   parse_method_type("(?String) -> untyped").params & parse_method_type("(*Integer) -> untyped").params

      # rest:required
      assert_equal parse_method_type("(String & Integer) -> untyped").params,
                   parse_method_type("(*String) -> untyped").params & parse_method_type("(Integer) -> untyped").params

      # rest:none
      assert_equal parse_method_type("() -> untyped").params,
                   parse_method_type("(*String) -> untyped").params & parse_method_type("() -> untyped").params

      # rest:opt
      assert_equal parse_method_type("(?String & Integer) -> untyped").params,
                   parse_method_type("(*String) -> untyped").params & parse_method_type("(?Integer) -> untyped").params

      # rest:rest
      assert_equal parse_method_type("(*String & Integer) -> untyped").params,
                   parse_method_type("(*String) -> untyped").params & parse_method_type("(*Integer) -> untyped").params

      ## Keywords

      # req:req
      assert_equal parse_method_type("(foo: String & Integer) -> untyped").params,
                   parse_method_type("(foo: String) -> untyped").params & parse_method_type("(foo: Integer) -> untyped").params

      # req:opt
      assert_equal parse_method_type("(foo: String & Integer) -> untyped").params,
                   parse_method_type("(foo: String) -> untyped").params & parse_method_type("(?foo: Integer) -> untyped").params

      # req:none
      assert_nil parse_method_type("(foo: String) -> untyped").params & parse_method_type("() -> untyped").params

      # req:rest
      assert_equal parse_method_type("(foo: String & Integer) -> untyped").params,
                   parse_method_type("(foo: String) -> untyped").params & parse_method_type("(**Integer) -> untyped").params

      # opt:req
      assert_equal parse_method_type("(foo: String & Integer) -> untyped").params,
                   parse_method_type("(?foo: String) -> untyped").params & parse_method_type("(foo: Integer) -> untyped").params

      # opt:opt
      assert_equal parse_method_type("(?foo: String & Integer) -> untyped").params,
                   parse_method_type("(?foo: String) -> untyped").params & parse_method_type("(?foo: Integer) -> untyped").params

      # opt:none
      assert_equal parse_method_type("() -> untyped").params,
                   parse_method_type("(?foo: String) -> untyped").params & parse_method_type("() -> untyped").params

      # opt:rest
      assert_equal parse_method_type("(?foo: String & Integer) -> untyped").params,
                   parse_method_type("(?foo: String) -> untyped").params & parse_method_type("(**Integer) -> untyped").params

      # none:req
      assert_nil parse_method_type("() -> untyped").params & parse_method_type("(foo: String) -> untyped").params

      # none:opt
      assert_equal parse_method_type("() -> untyped").params,
                   parse_method_type("() -> untyped").params & parse_method_type("(?foo: Integer) -> untyped").params

      # none:rest
      assert_equal parse_method_type("() -> untyped").params,
                   parse_method_type("() -> untyped").params & parse_method_type("(**Integer) -> untyped").params

      # rest:req
      assert_equal parse_method_type("(foo: String & Integer) -> untyped").params,
                   parse_method_type("(**String) -> untyped").params & parse_method_type("(foo: Integer) -> untyped").params

      # rest:opt
      assert_equal parse_method_type("(?foo: String & Integer) -> untyped").params,
                   parse_method_type("(**String) -> untyped").params & parse_method_type("(?foo: Integer) -> untyped").params

      # rest:none
      assert_equal parse_method_type("() -> untyped").params,
                   parse_method_type("(**String) -> untyped").params & parse_method_type("() -> untyped").params

      # rest:rest
      assert_equal parse_method_type("(**String & Integer) -> untyped").params,
                   parse_method_type("(**String) -> untyped").params & parse_method_type("(**Integer) -> untyped").params
    end
  end

  def test_method_type_params_union
    with_factory do
      # required:required
      assert_equal parse_method_type("(String | Integer) -> untyped").params,
                   parse_method_type("(String) -> untyped").params | parse_method_type("(Integer) -> untyped").params

      # required:none
      assert_equal parse_method_type("(?String) -> void").params,
                   parse_method_type("(String) -> untyped").params | parse_method_type("() -> untyped").params

      # required:optional
      assert_equal parse_method_type("(?String | Integer) -> untyped").params,
                   parse_method_type("(String) -> untyped").params | parse_method_type("(?Integer) -> untyped").params

      # required:rest
      assert_equal parse_method_type("(?String | Integer) -> untyped").params,
                   parse_method_type("(String) -> untyped").params | parse_method_type("(*Integer) -> untyped").params

      # none:required
      assert_equal parse_method_type("(?String) -> untyped").params,
                   parse_method_type("() -> untyped").params | parse_method_type("(String) -> untyped").params

      # none:optional
      assert_equal parse_method_type("(?Integer) -> untyped").params,
                   parse_method_type("() -> untyped").params | parse_method_type("(?Integer) -> untyped").params

      # none:rest
      assert_equal parse_method_type("(*Integer) -> untyped").params,
                   parse_method_type("() -> untyped").params | parse_method_type("(*Integer) -> untyped").params

      # opt:required
      assert_equal parse_method_type("(?String | Integer) -> untyped").params,
                   parse_method_type("(?String) -> untyped").params | parse_method_type("(Integer) -> untyped").params

      # opt:none
      assert_equal parse_method_type("(?String) -> untyped").params,
                   parse_method_type("(?String) -> untyped").params | parse_method_type("() -> untyped").params

      # opt:opt
      assert_equal parse_method_type("(?String | Integer) -> untyped").params,
                   parse_method_type("(?String) -> untyped").params | parse_method_type("(?Integer) -> untyped").params

      # opt:rest
      assert_equal parse_method_type("(?String | Integer) -> untyped").params,
                   parse_method_type("(?String) -> untyped").params | parse_method_type("(*Integer) -> untyped").params

      # rest:required
      assert_equal parse_method_type("(?String | Integer) -> untyped").params,
                   parse_method_type("(*String) -> untyped").params | parse_method_type("(Integer) -> untyped").params

      # rest:none
      assert_equal parse_method_type("(*String) -> untyped").params,
                   parse_method_type("(*String) -> untyped").params | parse_method_type("() -> untyped").params

      # rest:opt
      assert_equal parse_method_type("(?String | Integer, *String) -> untyped").params,
                   parse_method_type("(*String) -> untyped").params | parse_method_type("(?Integer) -> untyped").params

      # rest:rest
      assert_equal parse_method_type("(*String | Integer) -> untyped").params,
                   parse_method_type("(*String) -> untyped").params | parse_method_type("(*Integer) -> untyped").params

      ## Keywords

      # req:req
      assert_equal parse_method_type("(foo: String | Integer) -> untyped").params,
                   parse_method_type("(foo: String) -> untyped").params | parse_method_type("(foo: Integer) -> untyped").params

      # req:opt
      assert_equal parse_method_type("(?foo: String | Integer) -> untyped").params,
                   parse_method_type("(foo: String) -> untyped").params | parse_method_type("(?foo: Integer) -> untyped").params

      # req:none
      assert_equal parse_method_type("(?foo: String) -> untyped").params,
                   parse_method_type("(foo: String) -> untyped").params | parse_method_type("() -> untyped").params

      # req:rest
      assert_equal parse_method_type("(?foo: String | Integer) -> untyped").params,
                   parse_method_type("(foo: String) -> untyped").params | parse_method_type("(**Integer) -> untyped").params

      # opt:req
      assert_equal parse_method_type("(?foo: String | Integer) -> untyped").params,
                   parse_method_type("(?foo: String) -> untyped").params | parse_method_type("(foo: Integer) -> untyped").params

      # opt:opt
      assert_equal parse_method_type("(?foo: String | Integer) -> untyped").params,
                   parse_method_type("(?foo: String) -> untyped").params | parse_method_type("(?foo: Integer) -> untyped").params

      # opt:none
      assert_equal parse_method_type("(?foo: String) -> untyped").params,
                   parse_method_type("(?foo: String) -> untyped").params | parse_method_type("() -> untyped").params

      # opt:rest
      assert_equal parse_method_type("(?foo: String | Integer) -> untyped").params,
                   parse_method_type("(?foo: String) -> untyped").params | parse_method_type("(**Integer) -> untyped").params

      # none:req
      assert_equal parse_method_type("(?foo: String) -> untyped").params,
                   parse_method_type("() -> untyped").params | parse_method_type("(foo: String) -> untyped").params

      # none:opt
      assert_equal parse_method_type("(?foo: Integer) -> untyped").params,
                   parse_method_type("() -> untyped").params | parse_method_type("(?foo: Integer) -> untyped").params

      # none:rest
      assert_equal parse_method_type("(**Integer) -> untyped").params,
                   parse_method_type("() -> untyped").params | parse_method_type("(**Integer) -> untyped").params

      # rest:req
      assert_equal parse_method_type("(?foo: String | Integer) -> untyped").params,
                   parse_method_type("(**String) -> untyped").params | parse_method_type("(foo: Integer) -> untyped").params

      # rest:opt
      assert_equal parse_method_type("(?foo: String | Integer) -> untyped").params,
                   parse_method_type("(**String) -> untyped").params | parse_method_type("(?foo: Integer) -> untyped").params

      # rest:none
      assert_equal parse_method_type("(**String) -> untyped").params,
                   parse_method_type("(**String) -> untyped").params | parse_method_type("() -> untyped").params

      # rest:rest
      assert_equal parse_method_type("(**String | Integer) -> untyped").params,
                   parse_method_type("(**String) -> untyped").params | parse_method_type("(**Integer) -> untyped").params
    end
  end

  def test_method_type_union
    with_factory do
      assert_equal parse_method_type("(String & Integer) -> (String | Symbol)"),
                   parse_method_type("(String) -> String") | parse_method_type("(Integer) -> Symbol")

      assert_nil parse_method_type("() -> String") | parse_method_type("(Integer) -> untyped")
      assert_equal parse_method_type("() -> bool"),
                   parse_method_type("() -> bot") | parse_method_type("() -> bool")
      assert_equal parse_method_type("() -> untyped"),
                   parse_method_type("() -> untyped") | parse_method_type("() -> String")

      assert_equal parse_method_type("() { (String | Integer) -> (Integer & Float) } -> (String | Symbol)"),
                   parse_method_type("() { (String) -> Integer } -> String") | parse_method_type("() { (Integer) -> Float } -> Symbol")

      assert_equal parse_method_type("() { (String | Integer, ?String) -> void } -> void"),
                   parse_method_type("() { (String, String) -> void } -> void") | parse_method_type("() { (Integer) -> void } -> void")

      assert_equal parse_method_type("() { (String | Integer) -> (Integer & Float) } -> (String | Symbol)"),
                   parse_method_type("() ?{ (String) -> Integer } -> String") | parse_method_type("() { (Integer) -> Float } -> Symbol")

      assert_equal parse_method_type("() ?{ (String) -> Integer } -> (String | Symbol)"),
                   parse_method_type("() ?{ (String) -> Integer } -> String") | parse_method_type("() -> Symbol")
    end
  end

  def test_method_type_union_poly
    skip
    assert_equal parse_method_type("[A, A_1, B] (Array[A] & Hash[A_1, B]) -> (String | Symbol)"),
                 parse_method_type("[A] (Array[A]) -> String") | parse_method_type("[A, B] (Hash[A, B]) -> Symbol")
  end

  def test_method_type_intersection
    with_factory do
      assert_equal parse_method_type("(String | Integer) -> (String & Symbol)"),
                   parse_method_type("(String) -> String") & parse_method_type("(Integer) -> Symbol")

      assert_equal parse_method_type("(?Integer) -> untyped"),
                   parse_method_type("() -> String") & parse_method_type("(Integer) -> untyped")

      assert_equal parse_method_type("() -> bot"),
                   parse_method_type("() -> bot") & parse_method_type("() -> bool")
      assert_equal parse_method_type("() -> untyped"),
                   parse_method_type("() -> untyped") & parse_method_type("() -> String")

      assert_equal parse_method_type("() { (String & Integer) -> (Integer | Float) } -> (String & Symbol)"),
                   parse_method_type("() { (String) -> Integer } -> String") & parse_method_type("() { (Integer) -> Float } -> Symbol")

      assert_nil parse_method_type("() { (String, String) -> void } -> void") & parse_method_type("() { (Integer) -> void } -> void")

      assert_equal parse_method_type("() ?{ (String & Integer) -> (Integer | Float) } -> (String & Symbol)"),
                   parse_method_type("() ?{ (String) -> Integer } -> String") & parse_method_type("() { (Integer) -> Float } -> Symbol")


    end
  end

  def test_method_type_plus
    with_factory do |factory|
      assert_equal parse_method_type("(String | Integer) -> untyped"),
                   parse_method_type("(String) -> untyped") + parse_method_type("(Integer) -> untyped")

      assert_equal parse_method_type("(?String | Integer) -> untyped"),
                   parse_method_type("(?String) -> untyped") + parse_method_type("(Integer) -> untyped")

      assert_equal parse_method_type("(?String) -> untyped"),
                   parse_method_type("(String) -> untyped") + parse_method_type("() -> untyped")

      assert_equal parse_method_type("(?String | Symbol, *Symbol) -> untyped"),
                   parse_method_type("(String) -> untyped") + parse_method_type("(*Symbol) -> untyped")

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
