# @type var x: Integer | String | Symbol

x = (_ = nil)

case x
when Integer, String
  # !expects NoMethodError: type=(::Integer | ::String), method=foobar
  x.foobar()
end

case x == (_ = 1)
when Integer
  # !expects NoMethodError: type=(::Integer | ::String | ::Symbol), method=foobar
  x.foobar
end

case x
when 1
  # !expects NoMethodError: type=(::Integer | ::String | ::Symbol), method=foobar
  x.foobar
end

case x
when String
  # !expects@+2 IncompatibleAnnotation: var_name=x, ::Integer <: ::String
  # @type var x: Integer
  x + 1
end

case x
when Object
  # !expects@+2 IncompatibleTypeCase: var_name=x, ::Object <: (::Integer | ::String | ::Symbol)
  # !expects NoMethodError: type=::Object, method=foobar
  x.foobar
end
