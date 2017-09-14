# @type var a: Integer

# !expects IncompatibleAssignment: lhs_type=Integer, rhs_type=Integer | String
a = case 1
    when 2
      1
    when 3
      nil
    else
      "string"
    end
