class Foo
  # @rbs (Integer, Integer) -> String
  def foo(x, y)
    (x + y).to_s
  end

  #: () -> String?
  def bar

  end

  # @rbs return: String?
  def baz

  end
end


foo = Foo.new
foo.foo(1, 2)
foo.foo(1, "2")
foo.foo(1, 2, "3")
