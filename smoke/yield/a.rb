class A
  # @type method foo: () { (Integer) -> Integer } -> untyped
  def foo()
    # @type var x: String

    x = yield(3)

    yield(x)
  end

  # @type method bar: () -> untyped
  def bar()
    yield 4
  end
end
