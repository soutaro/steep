require_relative "test_helper"

class InterfaceTest < Minitest::Test
  include TestHelper
  include FactoryHelper
  
  def method_params(source)
    parse_method_type(source).type.params
  end

  def test_method_type_params_plus
    with_factory do
      assert_equal method_params("(String | Integer) -> untyped"),
                   method_params("(String) -> untyped") + method_params("(Integer) -> untyped")

      assert_equal method_params("(?String | Integer | nil) -> untyped"),
                   method_params("(String) -> untyped") + method_params("(?Integer) -> untyped")

      assert_equal method_params("(?String | Integer | nil, *Integer) -> untyped"),
                   method_params("(String) -> untyped") + method_params("(*Integer) -> untyped")

      assert_equal method_params("(?String | nil) -> untyped"),
                   method_params("(String) -> untyped") + method_params("() -> untyped")

      assert_equal method_params("(?String | Integer | nil) -> untyped"),
                   method_params("(?String) -> untyped") + method_params("(Integer) -> untyped")

      assert_equal method_params("(?String | Integer) -> untyped"),
                   method_params("(?String) -> untyped") + method_params("(?Integer) -> untyped")

      assert_equal method_params("(?String | Integer, *Integer) -> untyped"),
                   method_params("(?String) -> untyped") + method_params("(*Integer) -> untyped")

      assert_equal method_params("(?String) -> untyped"),
                   method_params("(?String) -> untyped") + method_params("() -> untyped")

      assert_equal method_params("(?String | Integer | nil, *String) -> untyped"),
                   method_params("(*String) -> untyped") + method_params("(Integer) -> untyped")

      assert_equal method_params("(?String | Integer, *String) -> untyped"),
                   method_params("(*String) -> untyped") + method_params("(?Integer) -> untyped")

      assert_equal method_params("(*String | Integer) -> untyped"),
                   method_params("(*String) -> untyped") + method_params("(*Integer) -> untyped")

      assert_equal method_params("(*String) -> untyped"),
                   method_params("(*String) -> untyped") + method_params("() -> untyped")

      assert_equal method_params("(?Integer?) -> untyped"),
                   method_params("() -> untyped") + method_params("(Integer) -> untyped")

      assert_equal method_params("(?Integer) -> untyped"),
                   method_params("() -> untyped") + method_params("(?Integer) -> untyped")

      assert_equal method_params("(*Integer) -> untyped"),
                   method_params("() -> untyped") + method_params("(*Integer) -> untyped")

      assert_equal method_params("() -> untyped"),
                   method_params("() -> untyped") + method_params("() -> untyped")
      
      assert_equal method_params("(foo: String | Integer) -> void"),
                   method_params("(foo: String) -> void") + method_params("(foo: Integer) -> untyped")

      assert_equal method_params("(?foo: String | Integer | nil) -> void"),
                   method_params("(foo: String) -> void") + method_params("(?foo: Integer) -> untyped")

      assert_equal method_params("(?foo: String | Integer | nil, **Integer) -> void"),
                   method_params("(foo: String) -> void") + method_params("(**Integer) -> untyped")

      assert_equal method_params("(?foo: String?) -> void"),
                   method_params("(foo: String) -> void") + method_params("() -> untyped")

      assert_equal method_params("(?foo: String | Integer | nil) -> void"),
                   method_params("(?foo: String) -> void") + method_params("(foo: Integer) -> untyped")

      assert_equal method_params("(?foo: String | Integer) -> void"),
                   method_params("(?foo: String) -> void") + method_params("(?foo: Integer) -> untyped")

      assert_equal method_params("(?foo: String | Integer, **Integer) -> void"),
                   method_params("(?foo: String) -> void") + method_params("(**Integer) -> untyped")

      assert_equal method_params("(?foo: String) -> void"),
                   method_params("(?foo: String) -> void") + method_params("() -> untyped")

      assert_equal method_params("(?foo: Integer | String | nil, **String) -> void"),
                   method_params("(**String) -> void") + method_params("(foo: Integer) -> untyped")

      assert_equal method_params("(?foo: Integer | String, **String) -> void"),
                   method_params("(**String) -> void") + method_params("(?foo: Integer) -> untyped")

      assert_equal method_params("(**String | Integer) -> void"),
                   method_params("(**String) -> void") + method_params("(**Integer) -> untyped")

      assert_equal method_params("(**String) -> void"),
                   method_params("(**String) -> void") + method_params("() -> untyped")

      assert_equal method_params("(?foo: Integer?) -> void"),
                   method_params("() -> void") + method_params("(foo: Integer) -> untyped")

      assert_equal method_params("(?foo: Integer) -> void"),
                   method_params("() -> void") + method_params("(?foo: Integer) -> untyped")

      assert_equal method_params("(**Integer) -> void"),
                   method_params("() -> void") + method_params("(**Integer) -> untyped")

      assert_equal method_params("() -> void"),
                   method_params("() -> void") + method_params("() -> untyped")
    end
  end

  def test_method_type_params_intersection
    with_factory do
      # req, none, opt, rest

      # required:required
      assert_equal method_params("(String & Integer) -> untyped"),
                   method_params("(String) -> untyped") & method_params("(Integer) -> untyped")

      # required:none
      assert_nil method_params("(String) -> untyped") & method_params("() -> untyped")

      # required:optional
      assert_equal method_params("(String & Integer) -> untyped"),
                   method_params("(String) -> untyped") & method_params("(?Integer) -> untyped")

      # required:rest
      assert_equal method_params("(String & Integer) -> untyped"),
                   method_params("(String) -> untyped") & method_params("(*Integer) -> untyped")

      # none:required
      assert_nil method_params("() -> untyped") & method_params("(String) -> void")

      # none:optional
      assert_equal method_params("() -> untyped"),
                   method_params("() -> untyped") & method_params("(?Integer) -> untyped")

      # none:rest
      assert_equal method_params("() -> untyped"),
                   method_params("() -> untyped") & method_params("(*Integer) -> untyped")

      # opt:required
      assert_equal method_params("(String & Integer) -> untyped"),
                   method_params("(?String) -> untyped") & method_params("(Integer) -> untyped")

      # opt:none
      assert_equal method_params("() -> untyped"),
                   method_params("(?String) -> untyped") & method_params("() -> untyped")

      # opt:opt
      assert_equal method_params("(?String & Integer) -> untyped"),
                   method_params("(?String) -> untyped") & method_params("(?Integer) -> untyped")

      # opt:rest
      assert_equal method_params("(?String & Integer) -> untyped"),
                   method_params("(?String) -> untyped") & method_params("(*Integer) -> untyped")

      # rest:required
      assert_equal method_params("(String & Integer) -> untyped"),
                   method_params("(*String) -> untyped") & method_params("(Integer) -> untyped")

      # rest:none
      assert_equal method_params("() -> untyped"),
                   method_params("(*String) -> untyped") & method_params("() -> untyped")

      # rest:opt
      assert_equal method_params("(?String & Integer) -> untyped"),
                   method_params("(*String) -> untyped") & method_params("(?Integer) -> untyped")

      # rest:rest

      assert_equal method_params("(*String & Integer) -> untyped"),
                   method_params("(*String) -> untyped") & method_params("(*Integer) -> untyped")

      ## Keywords

      # req:req
      assert_equal method_params("(foo: String & Integer) -> untyped"),
                   method_params("(foo: String) -> untyped") & method_params("(foo: Integer) -> untyped")

      # req:opt
      assert_equal method_params("(foo: String & Integer) -> untyped"),
                   method_params("(foo: String) -> untyped") & method_params("(?foo: Integer) -> untyped")

      # req:none
      assert_nil method_params("(foo: String) -> untyped") & method_params("() -> untyped")

      # req:rest
      assert_equal method_params("(foo: String & Integer) -> untyped"),
                   method_params("(foo: String) -> untyped") & method_params("(**Integer) -> untyped")

      # opt:req
      assert_equal method_params("(foo: String & Integer) -> untyped"),
                   method_params("(?foo: String) -> untyped") & method_params("(foo: Integer) -> untyped")

      # opt:opt
      assert_equal method_params("(?foo: String & Integer) -> untyped"),
                   method_params("(?foo: String) -> untyped") & method_params("(?foo: Integer) -> untyped")

      # opt:none
      assert_equal method_params("() -> untyped"),
                   method_params("(?foo: String) -> untyped") & method_params("() -> untyped")

      # opt:rest
      assert_equal method_params("(?foo: String & Integer) -> untyped"),
                   method_params("(?foo: String) -> untyped") & method_params("(**Integer) -> untyped")

      # none:req
      assert_nil method_params("() -> untyped") & method_params("(foo: String) -> untyped")

      # none:opt
      assert_equal method_params("() -> untyped"),
                   method_params("() -> untyped") & method_params("(?foo: Integer) -> untyped")

      # none:rest
      assert_equal method_params("() -> untyped"),
                   method_params("() -> untyped") & method_params("(**Integer) -> untyped")

      # rest:req
      assert_equal method_params("(foo: String & Integer) -> untyped"),
                   method_params("(**String) -> untyped") & method_params("(foo: Integer) -> untyped")

      # rest:opt
      assert_equal method_params("(?foo: String & Integer) -> untyped"),
                   method_params("(**String) -> untyped") & method_params("(?foo: Integer) -> untyped")

      # rest:none
      assert_equal method_params("() -> untyped"),
                   method_params("(**String) -> untyped") & method_params("() -> untyped")

      # rest:rest
      assert_equal method_params("(**String & Integer) -> untyped"),
                   method_params("(**String) -> untyped") & method_params("(**Integer) -> untyped")
    end
  end

  def test_method_type_params_union
    with_factory do
      # required:required
      assert_equal method_params("(String | Integer) -> untyped"),
                   method_params("(String) -> untyped") | method_params("(Integer) -> untyped")

      # required:none
      assert_equal method_params("(?String) -> void"),
                   method_params("(String) -> untyped") | method_params("() -> untyped")

      # required:optional
      assert_equal method_params("(?String | Integer) -> untyped"),
                   method_params("(String) -> untyped") | method_params("(?Integer) -> untyped")

      # required:rest
      assert_equal method_params("(?String | Integer, *Integer) -> untyped"),
                   method_params("(String) -> untyped") | method_params("(*Integer) -> untyped")

      # none:required
      assert_equal method_params("(?String) -> untyped"),
                   method_params("() -> untyped") | method_params("(String) -> untyped")

      # none:optional
      assert_equal method_params("(?Integer) -> untyped"),
                   method_params("() -> untyped") | method_params("(?Integer) -> untyped")

      # none:rest
      assert_equal method_params("(*Integer) -> untyped"),
                   method_params("() -> untyped") | method_params("(*Integer) -> untyped")

      # opt:required
      assert_equal method_params("(?String | Integer) -> untyped"),
                   method_params("(?String) -> untyped") | method_params("(Integer) -> untyped")

      # opt:none
      assert_equal method_params("(?String) -> untyped"),
                   method_params("(?String) -> untyped") | method_params("() -> untyped")

      # opt:opt
      assert_equal method_params("(?String | Integer) -> untyped"),
                   method_params("(?String) -> untyped") | method_params("(?Integer) -> untyped")

      # opt:rest
      assert_equal method_params("(?String | Integer) -> untyped"),
                   method_params("(?String) -> untyped") | method_params("(*Integer) -> untyped")

      # rest:required
      assert_equal method_params("(?String | Integer, *String) -> untyped"),
                   method_params("(*String) -> untyped") | method_params("(Integer) -> untyped")

      # rest:none
      assert_equal method_params("(*String) -> untyped"),
                   method_params("(*String) -> untyped") | method_params("() -> untyped")

      # rest:opt
      assert_equal method_params("(?String | Integer, *String) -> untyped"),
                   method_params("(*String) -> untyped") | method_params("(?Integer) -> untyped")

      # rest:rest
      assert_equal method_params("(*String | Integer) -> untyped"),
                   method_params("(*String) -> untyped") | method_params("(*Integer) -> untyped")

      ## Keywords

      # req:req
      assert_equal method_params("(foo: String | Integer) -> untyped"),
                   method_params("(foo: String) -> untyped") | method_params("(foo: Integer) -> untyped")

      # req:opt
      assert_equal method_params("(?foo: String | Integer) -> untyped"),
                   method_params("(foo: String) -> untyped") | method_params("(?foo: Integer) -> untyped")

      # req:none
      assert_equal method_params("(?foo: String) -> untyped"),
                   method_params("(foo: String) -> untyped") | method_params("() -> untyped")

      # req:rest
      assert_equal method_params("(?foo: String | Integer, **Integer) -> untyped"),
                   method_params("(foo: String) -> untyped") | method_params("(**Integer) -> untyped")

      # opt:req
      assert_equal method_params("(?foo: String | Integer) -> untyped"),
                   method_params("(?foo: String) -> untyped") | method_params("(foo: Integer) -> untyped")

      # opt:opt
      assert_equal method_params("(?foo: String | Integer) -> untyped"),
                   method_params("(?foo: String) -> untyped") | method_params("(?foo: Integer) -> untyped")

      # opt:none
      assert_equal method_params("(?foo: String) -> untyped"),
                   method_params("(?foo: String) -> untyped") | method_params("() -> untyped")

      # opt:rest
      assert_equal method_params("(?foo: String | Integer, **Integer) -> untyped"),
                   method_params("(?foo: String) -> untyped") | method_params("(**Integer) -> untyped")

      # none:req
      assert_equal method_params("(?foo: String) -> untyped"),
                   method_params("() -> untyped") | method_params("(foo: String) -> untyped")

      # none:opt
      assert_equal method_params("(?foo: Integer) -> untyped"),
                   method_params("() -> untyped") | method_params("(?foo: Integer) -> untyped")

      # none:rest
      assert_equal method_params("(**Integer) -> untyped"),
                   method_params("() -> untyped") | method_params("(**Integer) -> untyped")

      # rest:req
      assert_equal method_params("(?foo: String | Integer, **String) -> untyped"),
                   method_params("(**String) -> untyped") | method_params("(foo: Integer) -> untyped")

      # rest:opt
      assert_equal method_params("(?foo: String | Integer, **String) -> untyped"),
                   method_params("(**String) -> untyped") | method_params("(?foo: Integer) -> untyped")

      # rest:none
      assert_equal method_params("(**String) -> untyped"),
                   method_params("(**String) -> untyped") | method_params("() -> untyped")

      # rest:rest
      assert_equal method_params("(**String | Integer) -> untyped"),
                   method_params("(**String) -> untyped") | method_params("(**Integer) -> untyped")
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
    with_factory do
      assert_method_type(
        "[A, A(n), B(m)] ((Array[A] & Hash[A(n), B(m)])) -> (String | Symbol)",
        parse_method_type("[A] (Array[A]) -> String") | parse_method_type("[A, B] (Hash[A, B]) -> Symbol")
      )
    end
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

  def test_method_type_intersection_poly
    with_factory do
      assert_method_type(
        "[A, A(i) < Array[Integer]] ((A | A(i))) -> (A & Integer)",
        parse_method_type("[A] (A) -> A") & parse_method_type("[A < Array[Integer]] (A) -> Integer")
      )
    end
  end

  def test_method_type_plus
    with_factory do |factory|
      assert_equal parse_method_type("(String | Integer) -> untyped"),
                   parse_method_type("(String) -> untyped") + parse_method_type("(Integer) -> untyped")

      assert_equal parse_method_type("(?String | Integer | nil) -> untyped"),
                   parse_method_type("(?String) -> untyped") + parse_method_type("(Integer) -> untyped")

      assert_equal parse_method_type("(?String | nil) -> untyped"),
                   parse_method_type("(String) -> untyped") + parse_method_type("() -> untyped")

      assert_equal parse_method_type("(?String | Symbol | nil, *Symbol) -> untyped"),
                   parse_method_type("(String) -> untyped") + parse_method_type("(*Symbol) -> untyped")

      assert_equal parse_method_type("(?String | Symbol | nil, *Symbol) -> (Array | Hash)"),
                   parse_method_type("(String) -> Hash") + parse_method_type("(*Symbol) -> Array")

      assert_equal parse_method_type("(name: String | Symbol, ?email: String | Array | nil, ?age: Integer | Object | nil, **Array | Object) -> void"),
                   parse_method_type("(name: String, email: String, **Object) -> void") + parse_method_type("(name: Symbol, age: Integer, **Array) -> void")

      assert_equal parse_method_type("() ?{ (String | Integer) -> (Array | Hash) } -> void"),
                   parse_method_type("() ?{ (String) -> Array } -> void") + parse_method_type("() { (Integer) -> Hash } -> void")
    end
  end

  def test_method_type_params_poly
    with_factory do |factory|
      assert_method_type(
        "[A(n)] () ?{ (String) -> A(n) } -> (String | A(n))",
        parse_method_type("() -> String") + parse_method_type("[A] { (String) -> A } -> A")
      )
    end
  end
end
