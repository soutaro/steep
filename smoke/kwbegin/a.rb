# @type var a: Integer

# !expects IncompatibleAssignment: lhs_type=::Integer, rhs_type=::String
a = begin
  # @type var x: String
  x = '1'
  x
end
