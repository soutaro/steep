# @type var foo: Foo
foo = (_ = nil)

# @type var integer: Integer

# Foo#f returns String because overridden
# !expects IncompatibleAssignment: lhs_type=::Integer, rhs_type=::String
integer = foo.f()

# String#f returns Object because Object(X)#f is used
# !expects IncompatibleAssignment: lhs_type=::Integer, rhs_type=::Object
integer = "".f()
