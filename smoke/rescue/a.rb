# @type var a: Integer

# !expects IncompatibleAssignment: lhs_type=::Integer, rhs_type=(::String | ::Integer)
a = begin
      'foo'
    rescue
      1
    end

# @type var b: Integer

# !expects IncompatibleAssignment: lhs_type=::Integer, rhs_type=(::String | ::Integer)
b = 'foo' rescue 1

# @type var c: Integer

# !expects IncompatibleAssignment: lhs_type=::Integer, rhs_type=(::String | ::Symbol | ::Integer)
c = begin
      'foo'
    rescue RuntimeError
      :sym
    rescue StandardError
      1
    end

# @type var e: Integer

# !expects IncompatibleAssignment: lhs_type=::Integer, rhs_type=(::Array[::Integer] | ::Symbol | ::Integer)
e = begin
      'foo'
    rescue RuntimeError
      :sym
    rescue StandardError
      1
    else
      [1]
    end

# @type method foo: (String) -> String

# !expects MethodBodyTypeMismatch: method=foo, expected=::String, actual=(::Integer | ::String)
def foo(a)
  10
rescue
  'foo'
end

# when empty
begin
rescue
else
ensure
end
