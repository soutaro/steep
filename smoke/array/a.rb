# @type var a: Array[Integer]

a = []
a[1] = 3

# !expects ArgumentTypeMismatch: receiver=::Array[::Integer], expected=::Integer, actual=::String
a[2] = "foo"

# @type var i: Integer
i = a[0]

# @type var s: String
# !expects IncompatibleAssignment: lhs_type=::String, rhs_type=::Integer
s = a[1]


b = ["a", "b", "c"]

s = b[0]
# !expects IncompatibleAssignment: lhs_type=::Integer, rhs_type=::String
i = b[1]
