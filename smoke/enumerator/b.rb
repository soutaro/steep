# @type var b: Array[String]
# @type var c: Array[Integer]

a = [1]

# !expects* UnsatisfiableConstraint:
b = a.each.with_object([]) do |i, xs|
  # @type var xs: String
  xs << i.to_s
end

# !expects IncompatibleAssignment: lhs_type=::Array[::Integer], rhs_type=::Array[::String]
c = a.each.with_object([]) do |i, xs|
  # @type var xs: Array[String]
  xs << i.to_s
end

# @type var d: String
# !expects IncompatibleAssignment: lhs_type=::String, rhs_type=::Array[any]
d = a.each.with_object([]) do |i, xs|
  xs << i.to_s
end
