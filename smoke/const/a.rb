# @type const A: Integer
# @type var x: String

# !expects IncompatibleAssignment: lhs_type=String, rhs_type=Integer
x = A

x = B
