# @type var x: foo
x = ""

# !expects NoMethodError: type=foo, method=+
x + 123

# @type var y: bar<Integer>
y = x
y = []
