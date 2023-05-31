# @type var a: Integer

a = -> (x, y) do
  # @type var x: String
  # @type var y: String
  x + y
end["foo", "bar"]

# @type var c: ^(Integer) -> Integer
c = -> (x) { x + 1 }
