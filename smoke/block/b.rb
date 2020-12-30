# @type var a: A
a = (_ = nil)

a.bar do |x|
  break 3
end

# @type var s: ::String

s = a.bar do |x|
  # @type break: ::Integer
  break 3
end
