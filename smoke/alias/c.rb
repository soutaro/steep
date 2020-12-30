# @type var x: String

x = AliasMethodArg.new.foo(:foo)

# @type var name: name
name = :bar

x = AliasMethodArg.new.foo(name)
