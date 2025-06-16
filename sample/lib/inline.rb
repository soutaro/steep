class Foo
  # @rbs (Integer, Integer) -> String
  def foo(x, y)
    (x + y).to_s
  end
end


foo = Foo.new
foo.foo(1, 2)
foo.foo(1, "2")
foo.foo(1, 2, "3")
