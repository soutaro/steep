# ALLOW FAILURE

d = Set.new([1,2,3], &:to_s)
# !expects NoMethodError: type=::Set[::String], method=ffffffff
d.ffffffff

d.divide do |x, y|
  # !expects NoMethodError: type=::String, method=ggggg
  x.ggggg

  # !expects NoMethodError: type=::String, method=ggggg
  y.ggggg
end

d.divide do |x|
  # !expects NoMethodError: type=::String, method=ggggg
  x.ggggg
end
