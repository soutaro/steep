{ foo: "bar" }.each do |x, y|
  # @type var x1: Symbol
  # @type var y1: String

  x1 = x
  y1 = y
end

{ foo: "bar" }.each.with_index do |x, y|
  # @type var a: Symbol
  # @type var b: String
  # @type var c: Integer

  a = x[0]
  b = x[1]
  c = y
end
