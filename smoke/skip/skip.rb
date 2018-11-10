__skip__ = begin
  self.no_such_method
end

# @type var foo: String

foo = _ = begin
  # !expects NoMethodError: type=::Object, method=no_such_method
  self.no_such_method
end

foo = __any__ = begin
  # !expects NoMethodError: type=::Object, method=no_such_method
  self.no_such_method
end
