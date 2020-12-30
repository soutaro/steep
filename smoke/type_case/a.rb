# @type var x: Integer | String | Symbol

x = (_ = nil)

case x
when Integer, String
  x.foobar()
end

case x == (_ = 1)
when Integer
  x.foobar
end

case x
when 1
  x.foobar
end

case x
when String
  # @type var x: Integer
  x + 1
end
