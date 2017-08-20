# @type var a: A

a = A.new

# @type var i: Integer
# @type var s: String

# !expects IncompatibleAssignment: lhs_type=String, rhs_type=Integer
s = a.foo

# !expects IncompatibleAssignment: lhs_type=Integer, rhs_type=String
i = a.foo { nil }
