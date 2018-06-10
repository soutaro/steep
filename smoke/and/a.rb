# @type var b: String
# @type var c: ::Integer

a = "foo"

# !expects IncompatibleAssignment: lhs_type=::String, rhs_type=(::String | nil)
b = a && a.to_str

# !expects IncompatibleAssignment: lhs_type=::Integer, rhs_type=(::String | nil)
c = a && a.to_str

