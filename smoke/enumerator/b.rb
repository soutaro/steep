# @type var b: Array[String]
# @type var c: Array[Integer]

a = [1]

b = a.each.with_object([]) do |i, xs|
  xs << i.to_s
end

c = a.each.with_object([]) do |i, xs|
  xs << i.to_s
end

# @type var d: String
d = a.each.with_object([]) do |i, xs|
  xs << i.to_s
end
