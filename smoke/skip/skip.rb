__skip__ = begin
  self.no_such_method
end

# @type var foo: String

foo = _ = begin
  self.no_such_method
end

foo = __any__ = begin
  self.no_such_method
end
