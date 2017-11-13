require "test_helper"

class BufferTest < Minitest::Test
  Buffer = Steep::AST::Buffer

  def test_pos_to_loc
    buf = Buffer.new(name: "foo", content: <<-EOC)
def add(x, y)
  x + y

end
    EOC

    assert_equal [1, 0], buf.pos_to_loc(0)
    assert_equal [2, 0], buf.pos_to_loc(14)
    assert_equal [1, 13], buf.pos_to_loc(13)
    assert_equal [3, 0], buf.pos_to_loc(22)
    assert_equal [4, 0], buf.pos_to_loc(23)
  end

  def test_loc_to_pos
    buf = Buffer.new(name: "foo", content: <<-EOC)
def add(x, y)
  x + y

end
    EOC

    assert_equal 0, buf.loc_to_pos([1, 0])
    assert_equal 14, buf.loc_to_pos([2, 0])
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
