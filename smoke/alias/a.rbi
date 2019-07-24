type foo = String | Integer
type bar = Array[Integer] | foo
type baz = [String, Symbol]

type name = :foo | :bar

class AliasMethodArg
  def foo: (name) -> Integer
         | (Symbol) -> String
end
