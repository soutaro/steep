# @type var a: String

x = y = z = (_ = nil)

a = if x
      :foo
    end

if y
  :foo
else
  "baz"
end

a = if z
      "foofoo"
    else
      3
    end

