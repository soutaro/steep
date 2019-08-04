# @type var hash: Hash[Symbol, String]

a = [1]

# !expects IncompatibleAssignment: lhs_type=::Hash[::Symbol, ::String], rhs_type=::String
hash = a.each.with_object("") do |x, y|
  # !expects IncompatibleAssignment: lhs_type=::Hash[::Symbol, ::String], rhs_type=::Integer
  hash = x
  # !expects IncompatibleAssignment: lhs_type=::Hash[::Symbol, ::String], rhs_type=::String
  hash = y
end

# !expects IncompatibleAssignment: lhs_type=::Hash[::Symbol, ::String], rhs_type=::Array[::Integer]
hash = a.each.with_index do |x, y|
  # !expects IncompatibleAssignment: lhs_type=::Hash[::Symbol, ::String], rhs_type=::Integer
  hash = x
  # !expects IncompatibleAssignment: lhs_type=::Hash[::Symbol, ::String], rhs_type=::Integer
  hash = y
end
