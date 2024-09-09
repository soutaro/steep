x = [1, ""].find { true }

case x
when Integer
  "Integer"
when String
  "String"
when nil
  "nil"
else
  raise "Unexpected value"
end
