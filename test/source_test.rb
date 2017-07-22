require "test_helper"

class SourceTest < Minitest::Test
  A = Steep::Annotation
  T = Steep::Types

  def test_foo
    source = <<-EOF
# @type x1: any

module Foo
  # @type x2: any

  class Bar
    # @type x3: any
    # @type foo: -> any
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
    assert_equal [A::VarType.new(var: :x1, type: T::Any.new)], s.annotations(block: s.node).annotations
    # module
    assert_equal [A::VarType.new(var: :x2, type: T::Any.new)], s.annotations(block: s.node.children[0]).annotations
    # class
    assert_equal [
                   A::VarType.new(var: :x3, type: T::Any.new),
                   A::MethodType.new(method: :foo, type: Steep::Parser.parse_method("-> any"))
                 ], s.annotations(block: s.node.children[0].children[1]).annotations
    # def
    assert_equal [A::VarType.new(var: :x4, type: T::Any.new)], s.annotations(block: s.node.children[0].children[1].children[2]).annotations
    # block
    assert_equal [A::VarType.new(var: :x5, type: T::Any.new)], s.annotations(block: s.node.children[0].children[1].children[2].children[2]).annotations
  end
end
