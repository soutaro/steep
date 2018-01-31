# @type var x: String
# @type var y: Integer

# !expects IncompatibleAssignment: lhs_type=::String, rhs_type=::Integer
x = 1

# !expects IncompatibleAssignment: lhs_type=::String, rhs_type=::Symbol
x = :foo

# !expects IncompatibleAssignment: lhs_type=::Integer, rhs_type=::String
y = "foo"

# !expects IncompatibleAssignment: lhs_type=::String, rhs_type=_Boolean
x = true
# !expects IncompatibleAssignment: lhs_type=::Integer, rhs_type=_Boolean
y = false
