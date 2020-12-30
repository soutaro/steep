# @type var hash: Hash[Symbol, String]

a = [1]

hash = a.each.with_object("") do |x, y|
  hash = x
  hash = y
end

hash = a.each.with_index do |x, y|
  hash = x
  hash = y
end
