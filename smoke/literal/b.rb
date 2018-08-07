l = LiteralMethods.new

l.foo(3)
# !expects ArgumentTypeMismatch: receiver=::LiteralMethods, expected=3, actual=::Integer
l.foo(4)

l.bar(foo: :foo)
# !expects ArgumentTypeMismatch: receiver=::LiteralMethods, expected=:foo, actual=::Symbol
l.bar(foo: :bar)
