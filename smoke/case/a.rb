# @type var a: Integer

# !expects IncompatibleAssignment: lhs_type=::Integer, rhs_type=(::Array<::String> | ::Integer | ::String)
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

a = case
    # !expects ArgumentTypeMismatch: expected=::Integer, actual=::String
    when 1+"a"
      nil
    end
