class IncompatibleChild
  def foo(arg)
    # @type var x: Symbol
    # !expects IncompatibleAssignment: lhs_type=::Symbol, rhs_type=::Integer
    x = super()

    "123"
  end

  def initialize()
    # !expects IncompatibleArguments: receiver=::IncompatibleChild, method_type=(name: ::String) -> any
    super()

    # !expects IncompatibleZuper: method=initialize
    super
  end
end
