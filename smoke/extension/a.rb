# @type var foo: Foo

foo = (_ = nil)

foo.try do |x|
  # @type var string: String

  string = x
end

