# @type var a: [Integer, String]
# @type var b: String

a = [1, "foo"]
a[0] = 3

# !expects ArgumentTypeMismatch: type=[Integer, String], method=[]=
a[1] = 3

# !expects IncompatibleAssignment: lhs_type=String, rhs_type=Integer
b = a[0]

b = a[1]
