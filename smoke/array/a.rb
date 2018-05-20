# @type var a: Array<Integer>

a = []
a[1] = 3

# !expects ArgumentTypeMismatch: expected=::Integer, actual=::String
a[2] = "foo"

# @type var i: Integer
# !expects IncompatibleAssignment: lhs_type=::Integer, rhs_type=(::Integer | ::NilClass)
i = a[0]

# @type var s: String
# !expects IncompatibleAssignment: lhs_type=::String, rhs_type=(::Integer | ::NilClass)
s = a[1]


b = ["a", "b", "c"]

# !expects IncompatibleAssignment: lhs_type=::String, rhs_type=(::NilClass | ::String)
s = b[0]
# !expects IncompatibleAssignment: lhs_type=::Integer, rhs_type=(::NilClass | ::String)
i = b[1]
