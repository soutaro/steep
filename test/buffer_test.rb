require "test_helper"

class BufferTest < Minitest::Test
  Buffer = Steep::AST::Buffer

  def test_ranges
    buf = Buffer.new(name: "foo", content: <<-EOC)
123
4567

    EOC

    assert_equal 0..3, buf.ranges[0]
    assert_equal 4..8, buf.ranges[1]
    assert_equal 9..9, buf.ranges[2]
    assert_equal 10..10, buf.ranges[3]

    assert_equal "123", buf.lines[0]
    assert_equal "4567", buf.lines[1]
    assert_equal "", buf.lines[2]
    assert_equal "", buf.lines[3]
  end

  def test_pos_to_loc
    buf = Buffer.new(name: "foo", content: <<-EOC)
def add(x, y)
  x + y

end
    EOC

    assert_equal [1, 0], buf.pos_to_loc(0)
    assert_equal [1, 13], buf.pos_to_loc(13)
    assert_equal [2, 0], buf.pos_to_loc(14)
    assert_equal [3, 0], buf.pos_to_loc(22)
    assert_equal [4, 0], buf.pos_to_loc(23)
    assert_equal [4, 3], buf.pos_to_loc(26)
    assert_equal [5, 0], buf.pos_to_loc(27)
  end

  def test_loc_to_pos
    buf = Buffer.new(name: "foo", content: <<-EOC)
def add(x, y)
  x + y
end
    EOC

    assert_equal 0, buf.loc_to_pos([1, 0])
    assert_equal 13, buf.loc_to_pos([1, 13])
    assert_equal 14, buf.loc_to_pos([2, 0])
    assert_equal 21, buf.loc_to_pos([2, 7])
    assert_equal 22, buf.loc_to_pos([3, 0])
    assert_equal 25, buf.loc_to_pos([3, 3])
    assert_equal 26, buf.loc_to_pos([4, 0])
  end

  def test_source
    buf = Buffer.new(name: "foo", content: <<-EOC)
def add(x, y)
  x + y

end
    EOC

    assert_equal "  x + y\n", buf.source(buf.loc_to_pos([2, 0])...buf.loc_to_pos([3, 0]))
  end
end
