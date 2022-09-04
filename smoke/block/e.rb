123.instance_eval do
  self - 1
end

b = BlockWithSelf.new.instance_exec do
  @name = ""
  @id = 123
end

[1, ""][0].instance_eval do
  foo()
end
