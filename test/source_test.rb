require "test_helper"

class SourceTest < Minitest::Test
  A = Steep::Annotation
  T = Steep::Types

  include TestHelper

  def test_foo
    source = <<-EOF
# @type var x1: any

module Foo
  # @type var x2: any

  class Bar
    # @type var x3: any
    # @type method foo: -> any
    def foo
      # @type return: any
      # @type var x4: any
      self.tap do
        # @type var x5: any
        # @type block: Integer
      end
    end
  end
end

Foo::Bar.new
    EOF

    s = Steep::Source.parse(source, path: Pathname("foo.rb"))

    # toplevel
    assert_any s.annotations(block: s.node) do |a| a.is_a?(A::VarType) && a.var == :x1 && a.type == T::Any.new end
    # module
    assert_any s.annotations(block: s.node.children[0]) do |a| a == A::VarType.new(var: :x2, type: T::Any.new) end
    # class
    class_annotations = s.annotations(block: s.node.children[0].children[1])
    assert_equal 2, class_annotations.size
    assert_includes class_annotations, A::VarType.new(var: :x3, type: T::Any.new)
    assert_includes class_annotations, A::MethodType.new(method: :foo, type: Steep::Parser.parse_method("-> any"))

    # def
    def_annotations = s.annotations(block: s.node.children[0].children[1].children[2])
    assert_equal 2, def_annotations.size
    assert_includes def_annotations, A::VarType.new(var: :x4, type: T::Any.new)
    assert_includes def_annotations, A::ReturnType.new(type: T::Any.new)

    # block
    block_annotations = s.annotations(block: s.node.children[0].children[1].children[2].children[2])
    assert_equal 2, block_annotations.size
    assert_includes block_annotations, A::VarType.new(var: :x5, type: T::Any.new)
    assert_includes block_annotations, A::BlockType.new(type: T::Name.new(name: :Integer, params: []))
  end
end
