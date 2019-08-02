# @type var a: Integer
# @type var b: Integer

# !expects IncompatibleAssignment: lhs_type=::Integer, rhs_type=::String
a = begin
      'foo'
    ensure
      # !expects IncompatibleAssignment: lhs_type=::Integer, rhs_type=::Symbol
      b = :foo
      1
    end

# @type method foo: (String) -> String

# !expects MethodBodyTypeMismatch: method=foo, expected=::String, actual=::Integer
def foo(a)
  10
ensure
  # !expects* UnresolvedOverloading: receiver=::Integer, method_name=+,
  1 + '1'
  a
end
