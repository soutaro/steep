# !expects NoMethodError: type=::Integer, method=fffffffffffff
Foo.new.get({ foo: 3 }).fffffffffffff
