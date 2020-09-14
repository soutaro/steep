# @type var x: foo
x = ""

# !expects* UnresolvedOverloading: receiver=(::String | ::Integer), method_name=+,
x + 123

# @type var y: bar
y = x
y = []

# @type var z: Symbol
case x
when String
  # !expects IncompatibleAssignment: lhs_type=::Symbol, rhs_type=::String
  z = x
when Integer
  # !expects IncompatibleAssignment: lhs_type=::Symbol, rhs_type=::Integer
  z = x
end
