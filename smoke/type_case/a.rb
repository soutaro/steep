# @type var x: Integer | String | Symbol

x = nil

case x
when Integer, String
  # !expects NoMethodError: type=(::Integer | ::String), method=foobar
  x.foobar()
end

case x == 1
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
  # @type var x: Integer
  # !expects NoMethodError: type=::Integer, method=foobar
  x.foobar
end
