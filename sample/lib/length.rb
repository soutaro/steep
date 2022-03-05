class LengthCalculator
  def max0(x, y)
    if x.size > y.size
      x
    else
      y
    end
  end

  def max1(x, y)
    if x.size > y.size
      x
    else
      y
    end
  end

  def max2(x, y)
    if x.size > y.size
      x
    else
      y
    end
  end
end

calc = LengthCalculator.new()

calc.max0("foo", "bar")
calc.max1("foo", "bar")
calc.max2("foo", "bar")

calc.max0(true, false)
calc.max1(true, false)
calc.max2(true, false)
