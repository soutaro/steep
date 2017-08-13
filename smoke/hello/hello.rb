# @type var x: _Foo
# @type var y: _Bar

x = nil
y = nil

a = x.foo

# !expects NoMethodError: type=_Bar, method=foo
b = y.foo

# !expects IncompatibleAssignment: lhs_type=_Foo, rhs_type=_Bar
x = y
