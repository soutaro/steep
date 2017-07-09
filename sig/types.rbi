interface Method
end

interface Type
end

interface Block
end

interface Interface
end

interface SomeInterface
  def foo: (Integer) -> any
  def bar: (String, foo: any, ?bar: Numeric) { (String) -> Integer } -> Integer
end
