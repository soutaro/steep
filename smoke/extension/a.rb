# @type var foo: Foo

foo = (_ = nil)

foo.try do |x|
  # @type var string: String

  # !expects IncompatibleAssignment: lhs_type=::String, rhs_type=::Foo
  string = x
end

