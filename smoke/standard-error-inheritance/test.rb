# @type var foo: Foo
foo = (_ = nil)

# This should error - Foo doesn't have method 'baz'
foo.baz
