class Foo
  # @implements Foo

  def f()
    # @type var string: String
    # !expects IncompatibleAssignment: lhs_type=String, rhs_type=Object
    string = super()
  end
end
