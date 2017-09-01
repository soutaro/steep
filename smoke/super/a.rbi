class A
  def foo: (any) -> Integer
  include M

  def baz: () -> any
end

module M
  def foo: (any) -> Object
end
