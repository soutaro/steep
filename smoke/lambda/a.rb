# @type var a: Integer

# !expects IncompatibleAssignment: lhs_type=::Integer, rhs_type=::String
a = -> (x, y) do
  # @type var x: String
  # @type var y: String
  x + y
end["foo", "bar"]

# @type var b: ^(Integer) -> Integer
# !expects IncompatibleAssignment: lhs_type=^(::Integer) -> ::Integer, rhs_type=::Proc
b = lambda do |x|
  # !expects NoMethodError: type=nil, method=+
  x + 1 
end

# @type var c: ^(Integer) -> Integer
c = -> (x) { x + 1 }
