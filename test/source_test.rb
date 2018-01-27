require "test_helper"

class SourceTest < Minitest::Test
  A = Steep::AST::Annotation
  T = Steep::AST::Types

  include TestHelper

  def test_foo
    source = <<-EOF
# @type var x1: any

module Foo
  # @type var x2: any

  class Bar
    # @type instance: String
    # @type module: String.class

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

    # @type method bar: () -> any
    def bar
    end
  end
end

Foo::Bar.new
    EOF

    s = Steep::Source.parse(source, path: Pathname("foo.rb"))

    # toplevel
    assert_any s.annotations(block: s.node) do |a|
      a.is_a?(A::VarType) && a.name == :x1 && a.type == T::Any.new
    end

    # module
    assert_any s.annotations(block: s.node.children[0]) do |a|
      a == A::VarType.new(name: :x2, type: T::Any.new)
    end
    assert_nil s.annotations(block: s.node.children[0]).instance_type
    assert_nil s.annotations(block: s.node.children[0]).module_type

    # class
    class_annotations = s.annotations(block: s.node.children[0].children[1])
    assert_equal 5, class_annotations.size
    assert_equal T::Name.new_instance(name: :String), class_annotations.instance_type
    assert_equal T::Name.new_class(name: :String, constructor: nil), class_annotations.module_type
    assert_equal T::Any.new, class_annotations.lookup_var_type(:x3)
    assert_equal "-> any", class_annotations.lookup_method_type(:foo).location.source
    assert_equal "() -> any", class_annotations.lookup_method_type(:bar).location.source

    # def
    foo_annotations = s.annotations(block: s.node.children[0].children[1].children[2].children[0])
    assert_equal 2, foo_annotations.size
    assert_equal T::Any.new, foo_annotations.lookup_var_type(:x4)
    assert_equal T::Any.new, foo_annotations.return_type

    # block
    block_annotations = s.annotations(block: s.node.children[0].children[1].children[2].children[0].children[2])
    assert_equal 2, block_annotations.size
    assert_equal T::Any.new, block_annotations.lookup_var_type(:x5)
    assert_equal T::Name.new_instance(name: :Integer), block_annotations.block_type
  end
end
