# @type var x: Array[String?]

x = ["foo"]
x = [nil]

# !expects IncompatibleAssignment: lhs_type=::Array[(::String | nil)], rhs_type=::Array[::Integer]
x = [1]
