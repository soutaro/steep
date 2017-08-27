class A
  def foo(x)
    # @type self: A

    # @type var a: Integer
    # !expects IncompatibleAssignment: lhs_type=Integer, rhs_type=Object
    a = super(x)
    # !expects IncompatibleAssignment: lhs_type=Integer, rhs_type=Object
    a = super

    # @type var b: Object
    b = super(x)

    # @type var c: Integer
    c = foo(x)
  end

  def bar()
    # @type self: A

    # !expects UnexpectedSuper: method=bar
    super()
  end
end
