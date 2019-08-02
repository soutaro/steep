class A
  def foo: (String) -> any
  def bar: () -> String
  def self.baz: -> Integer
end

class B
  def name: -> String
end

class C
  def foo: -> instance
  def bar: -> instance
end

class D
  def initialize: (String) -> any
  def foo: -> any
end

class E
  def initialize: () -> any
  def foo: -> any
end
