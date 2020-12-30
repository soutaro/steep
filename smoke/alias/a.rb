# @type var x: foo
x = ""

x + 123

# @type var y: bar
y = x
y = []

# @type var z: Symbol
case x
when String
  z = x
when Integer
  z = x
end
