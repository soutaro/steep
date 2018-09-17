class A
  def foo: -> _Foo
  def hello: -> void
end

class A::Object
  def object?: -> bool
end

interface A::_Foo
  def foo: -> Object
end
