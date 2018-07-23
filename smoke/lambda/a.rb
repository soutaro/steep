# lambda syntax (->) will be ignored and have type of `any`.
a = -> () { 1 + "" }

# !expects NoMethodError: type=::Object, method=lambda
b = lambda {|x| x + 1 }
