# @type var a: A
a = (_ = nil)

a.bar do |x|
  # !expects BreakTypeMismatch: expected=::Symbol, actual=::Integer
  break 3
end

# @type var s: ::String

# !expects IncompatibleAssignment: lhs_type=::String, rhs_type=(::Integer | ::Symbol)
s = a.bar do |x|
  # @type break: ::Integer
  break 3
end
