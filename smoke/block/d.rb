# @type var a: ^(Integer) -> String
a = -> (x) { x.to_s }

# @type var b: Array[Float]

# !expects IncompatibleAssignment: lhs_type=::Array[::Float], rhs_type=::Array[::String]
b = [1,2,3].map(&a)

# !expects IncompatibleAssignment: lhs_type=::Array[::Float], rhs_type=::Array[::String]
b = [1,2,3].map(&:to_s)

# !expects* BlockTypeMismatch:
[1,2,3].map(&:no_such_method)
# !expects* BlockTypeMismatch:
[1,2,3].map(&:floor)
