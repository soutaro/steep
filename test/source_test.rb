require "test_helper"

class SourceTest < Minitest::Test
  def test_foo
    source = <<-EOF
# @type x1: any

module Foo
  # @type x2: any

  class Bar
    # @type x3: any
    def foo
      # @type x4: any
      self.tap do
        # @type x5: any
      end
    end
  end
end

Foo::Bar.new
    EOF

    s = Steep::Source.parse(source, path: Pathname("foo.rb"))

    # toplevel
    assert_equal [:x1], s.annotations(block: s.node).map(&:var)
    # module
    assert_equal [:x2], s.annotations(block: s.node.children[0]).map(&:var)
    # class
    assert_equal [:x3], s.annotations(block: s.node.children[0].children[1]).map(&:var)
    # def
    assert_equal [:x4], s.annotations(block: s.node.children[0].children[1].children[2]).map(&:var)
    # block
    assert_equal [:x5], s.annotations(block: s.node.children[0].children[1].children[2].children[2]).map(&:var)
  end
end
