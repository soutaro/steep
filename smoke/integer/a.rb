# @type var x: Numeric
x = _ = 1
integer_1 = Integer(x)
integer_1.foo

integer_2 = Integer("1")
integer_2.foo

class WithToInt
  def to_int; 1; end
end
integer_3 = Integer(WithToInt.new)
integer_3.foo

class WithToI
  def to_i; 1; end
end
integer_4 = Integer(WithToI.new)
integer_4.foo

integer_5 = Integer("10", 2)
integer_5.foo

Integer(Object.new)

Integer(nil)
