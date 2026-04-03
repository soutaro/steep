class SteepTest
  def union_fn
    :some_symbol
  end

  def test
    res = union_fn
    if res == :some_symbol
      puts "got symbol: #{res}"
    else
      puts "got string: #{res.str}"
    end
  end
end
