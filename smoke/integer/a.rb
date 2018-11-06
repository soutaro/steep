integer_1 = Integer(1)
# !expects NoMethodError: type=::Integer, method=foo
integer_1.foo

integer_2 = Integer("1")
# !expects NoMethodError: type=::Integer, method=foo
integer_2.foo

class WithToInt
  def to_int; 1; end
end
integer_3 = Integer(WithToInt.new)
# !expects NoMethodError: type=::Integer, method=foo
integer_3.foo

class WithToI
  def to_i; 1; end
end
integer_4 = Integer(WithToI.new)
# !expects NoMethodError: type=::Integer, method=foo
integer_4.foo

integer_5 = Integer("10", 2)
# !expects NoMethodError: type=::Integer, method=foo
integer_5.foo

# !expects IncompatibleArguments: receiver=::Object, method_type=(::String, ::Integer) -> ::Integer
Integer(Object.new)

# !expects IncompatibleArguments: receiver=::Object, method_type=(::String, ::Integer) -> ::Integer
Integer(nil)
