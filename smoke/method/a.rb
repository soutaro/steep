# @type method foo: (Integer, y: Integer) -> String

def foo(x, y:)
  # @type var z: String

  z = x

  z = y

  3
end

# @type method bar: (Integer) -> String

def bar(x, y)
  # @type var z: String

  z = x

  z = y
end
