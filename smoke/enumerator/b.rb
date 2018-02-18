# @type var b: Array<String>

a = [1]

# !expects BlockParameterTypeMismatch: expected=::Array<any>, actual=String
b = a.each.with_object([]) do |i, xs|
  # @type var xs: String
  xs << i.to_s
end
