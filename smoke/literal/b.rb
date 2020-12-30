l = LiteralMethods.new

l.foo(3)
l.foo(4)

l.bar(foo: :foo)
l.bar(foo: :bar)
