type foo = String | Integer
type bar<'a> = Array<'a> | foo
type baz = [String, Symbol]

type name = :foo | :bar

class AliasMethodArg
  def foo: (name) -> Integer
         | (Symbol) -> String
end
