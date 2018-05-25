# @type var b: String
# @type var c: ::Integer

a = "foo"

# !expects IncompatibleAssignment: lhs_type=::String, rhs_type=(::NilClass | ::String)
b = a && a.to_str

# !expects IncompatibleAssignment: lhs_type=::Integer, rhs_type=(::NilClass | ::String)
c = a && a.to_str

