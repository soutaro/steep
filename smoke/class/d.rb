# @type const A: A.class
# @type const B: A.class constructor
# @type const C: A.class noconstructor

# !expects NoMethodError: type=A.class, method=new
a = A.new
b = B.new
# !expects NoMethodError: type=A.class noconstructor, method=new
c = C.new
