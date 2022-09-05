# @type var a: Array[BlockParamSplit::pair[Integer, String]]
a = [[1, "a"]]

a.each do |x, y|
  x + 1
  y + "2"
end
