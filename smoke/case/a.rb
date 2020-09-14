# @type var a: Integer

# !expects IncompatibleAssignment: lhs_type=::Integer, rhs_type=(::Integer | ::Array[::String] | nil | ::String)
a = case 1
    when 2
      1
    when 0, 100
      ["String"]
    when 3
      nil
    when 4
    else
      "string"
    end

# !expects IncompatibleAssignment: lhs_type=::Integer, rhs_type=(::Integer | nil)
a = case
    # !expects* UnresolvedOverloading: receiver=::Integer, method_name=+,
    when 1+"a"
      30
    end
