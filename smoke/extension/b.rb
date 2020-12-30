# @type var foo: Foo
foo = (_ = nil)

# @type var integer: Integer

# Foo#f returns String because overridden
integer = foo.f()

# String#f returns Object because Object(X)#f is used
integer = "".f()
