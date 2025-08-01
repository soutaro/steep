
# This is a bar class
class Bar
  # @rbs () -> Integer
  def from_bar
    123
  end
end

class Foo2 < HelloWorld #[String]
  # @rbs (Integer, Integer) -> String
  def foo(x, y)
    (x + y).to_s
  end

  #: () -> untyped
  def bar

  end

  # @rbs return: String?
  def baz

  end

  # @rbs (Integer) -> void
  def initialize(x)
  end
end


foo = Foo.new(1)
foo.foo(1, 2)
foo.foo(1, "2")
foo.foo(1, 2, "3")

foo.hello_world
