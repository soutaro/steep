class IncompatibleChild
  def foo(arg)
    # @type var x: Symbol
    # !expects IncompatibleAssignment: lhs_type=::Symbol, rhs_type=::Integer
    x = super()

    "123"
  end

  def initialize()
    super()

    super
  end
end
