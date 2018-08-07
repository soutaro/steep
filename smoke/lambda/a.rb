# @type var a: Integer

# !expects IncompatibleAssignment: lhs_type=::Integer, rhs_type=::String
a = -> (x, y) do
  # @type var x: String
  # @type var y: String
  x + y
end["foo", "bar"]

# !expects NoMethodError: type=::Object, method=lambda
b = lambda {|x| x + 1 }
