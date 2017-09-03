# @type var b: String
# @type var c: Integer

a = "foo"

b = a && a.to_str

# !expects IncompatibleAssignment: lhs_type=Integer, rhs_type=String
c = a && a.to_str
