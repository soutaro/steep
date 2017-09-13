# @type const A: Integer
# @type var x: String

# !expects IncompatibleAssignment: lhs_type=String, rhs_type=Integer
x = A

x = B

module X
  # @type const A: Integer

  def foo
    # @type var x: String

    # !expects IncompatibleAssignment: lhs_type=String, rhs_type=Integer
    x = A

    x = B
  end
end


# @type const Foo::Bar::Baz: Integer

# !expects IncompatibleAssignment: lhs_type=String, rhs_type=Integer
x = Foo::Bar::Baz

z = Foo
x = z::Bar::Baz
x = ::Foo::Bar::Baz
