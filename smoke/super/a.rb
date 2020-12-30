class A
  def foo(x)
    # @type self: A

    # @type var a: Integer
    a = super(x)
    a = super

    # @type var b: Object
    b = super(x)

    # @type var c: Integer
    c = foo(x)
  end

  def bar()
    # @type self: A

    super()
    super
  end

  def baz
    # @type self: A

    super()

    super
  end
end
