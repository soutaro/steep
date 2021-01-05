x = [1, ""].sample

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
