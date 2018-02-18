# @type var a: A
a = nil

a.bar do |x|
  # !expects BreakTypeMismatch: expected=::Symbol, actual=::Integer
  break 3
end

# @type var s: ::String

# !expects IncompatibleAssignment: lhs_type=::String, rhs_type=(::Symbol | ::Integer)
s = a.bar do |x|
  # @type break: ::Integer
  break 3
end
