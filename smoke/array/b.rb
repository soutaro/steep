x = ""
y = 1

# !expects IncompatibleAssignment: lhs_type=::String, rhs_type=::Integer
x = y
# !expects IncompatibleAssignment: lhs_type=::Integer, rhs_type=::String
y = x

# @type var a: Array[Integer]
# @type var b: Array[String]

a = []
# !expects IncompatibleAssignment: lhs_type=::Array[::String], rhs_type=::Array[::Integer]
b = a
# !expects IncompatibleAssignment: lhs_type=::Array[::Integer], rhs_type=::Array[::String]
a = b
