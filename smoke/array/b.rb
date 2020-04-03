x = ""
y = 1

x = y
y = x

# @type var a: Array[Integer]
# @type var b: Array[String]

a = []
# !expects IncompatibleAssignment: lhs_type=::Array[::String], rhs_type=::Array[::Integer]
b = a
# !expects IncompatibleAssignment: lhs_type=::Array[::Integer], rhs_type=::Array[::String]
a = b
