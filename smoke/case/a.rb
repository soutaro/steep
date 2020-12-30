# @type var a: Integer

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
    when 1+"a"
      30
    end
