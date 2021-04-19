test = UnsatisfiableConstraint.new

test.foo([]) do |x|
  # @type var x: String
  x.foo()
end
