# @type method foo: (Integer, y: Integer) -> String

# !expects MethodBodyTypeMismatch: method=foo, expected=::String, actual=::Integer
def foo(x, y:)
  # @type var z: String

  # !expects IncompatibleAssignment: lhs_type=::String, rhs_type=::Integer
  z = x

  # !expects IncompatibleAssignment: lhs_type=::String, rhs_type=::Integer
  z = y

  3
end

# @type method bar: (Integer) -> String

# !expects MethodParameterTypeMismatch: method=bar
def bar(x, y)
  # @type var z: String

  # !expects IncompatibleAssignment: lhs_type=::String, rhs_type=::Integer
  z = x

  z = y
end
