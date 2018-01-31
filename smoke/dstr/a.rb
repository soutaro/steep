# @type var b: String

a = 0

# !expects NoMethodError: type=::Integer, method=foo
b = "Hello #{a.foo} world!"
