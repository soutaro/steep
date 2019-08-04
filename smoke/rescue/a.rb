# @type var a: Integer

# !expects IncompatibleAssignment: lhs_type=::Integer, rhs_type=(::Integer | ::String)
a = begin
      'foo'
    rescue
      1
    end

# @type var b: Integer

# !expects IncompatibleAssignment: lhs_type=::Integer, rhs_type=(::Integer | ::String)
b = 'foo' rescue 1

# @type var c: Integer

# !expects IncompatibleAssignment: lhs_type=::Integer, rhs_type=(::Integer | ::String | ::Symbol)
c = begin
      'foo'
    rescue RuntimeError
      :sym
    rescue StandardError
      1
    end

# @type var d: Integer

# !expects IncompatibleAssignment: lhs_type=::Integer, rhs_type=::String
d = begin
      1
    else
      'foo'
    end

# @type var e: Integer

# !expects IncompatibleAssignment: lhs_type=::Integer, rhs_type=(::Array[::Integer] | ::Integer | ::String | ::Symbol)
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
