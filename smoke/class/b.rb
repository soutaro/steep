# @var type s: String
# @var type a: Integer

s = "".class.allocate

# !expects IncompatibleAssignment: lhs_type=String, rhs_type=Integer
s = 3.class.allocate
