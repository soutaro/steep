class A
  # @type method foo: () { (Integer) -> Integer } -> any
  def foo()
    # @type var x: String

    # !expects IncompatibleAssignment: lhs_type=String, rhs_type=Integer
    x = yield(3)

    # !expects IncompatibleAssignment: lhs_type=Integer, rhs_type=String
    yield(x)
  end

  # @type method bar: () -> any
  def bar()
    # !expects UnexpectedYield
    yield 4
  end
end
