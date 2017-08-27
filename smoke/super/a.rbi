class A
  def foo: (any) -> Integer
  include M
end

module M
  def foo: (any) -> Object
end
