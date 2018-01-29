# @type var a: String

# !expects IncompatibleAssignment: lhs_type=String, rhs_type=Symbol
a = if x
      :foo
    end

if y
  :foo
else
  "baz"
end

# !expects IncompatibleAssignment: lhs_type=String, rhs_type=(String | Integer)
a = if z
      "foofoo"
    else
      3
    end

