# @type var x: String

# !expects IncompatibleAssignment: lhs_type=::String, rhs_type=::Integer
x = AliasMethodArg.new.foo(:foo)

# @type var name: name
name = :bar

# !expects IncompatibleAssignment: lhs_type=::String, rhs_type=::Integer
x = AliasMethodArg.new.foo(name)
