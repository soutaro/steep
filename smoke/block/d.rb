# @type var a: ^(Integer) -> String
a = -> (x) { x.to_s }

# @type var b: Array[Float]

b = [1,2,3].map(&a)

b = [1,2,3].map(&:to_s)

[1,2,3].map(&:no_such_method)
[1,2,3].map(&:divmod)
