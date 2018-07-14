# @type var a: baz

a = ["", :foo]

# @type var x: Integer
# !expects IncompatibleAssignment: lhs_type=::Integer, rhs_type=String
x = a[0]
