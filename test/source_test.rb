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

  def parse_source(src)
    Steep::Source.parse(src, path: Pathname("foo.rb"))
  end

  def test_if
    source = parse_source(<<-EOF)
if foo
  # @type var x: String
  x + "foo"
else
  # @type var y: Integer
  y + "foo"
end
    EOF

    source.node.yield_self do |node|
      annotations = source.annotations(block: node)
      assert_nil annotations.var_types[:x]
      assert_nil annotations.var_types[:y]
    end

    source.node.children[1].yield_self do |node|
      annotations = source.annotations(block: node)
      refute_nil annotations.var_types[:x]
      assert_nil annotations.var_types[:y]
    end

    source.node.children[2].yield_self do |node|
      annotations = source.annotations(block: node)
      assert_nil annotations.var_types[:x]
      refute_nil annotations.var_types[:y]
    end
  end

  def test_unless
    source = parse_source(<<-EOF)
unless foo then
  # @type var x: Integer
  x + 1
else
  # @type var y: String
  y + "foo"
end
    EOF

    source.node.yield_self do |node|
      annotations = source.annotations(block: node)
      assert_nil annotations.var_types[:x]
      assert_nil annotations.var_types[:y]
    end

    source.node.children[1].yield_self do |node|
      annotations = source.annotations(block: node)
      assert_nil annotations.var_types[:x]
      refute_nil annotations.var_types[:y]
    end

    source.node.children[2].yield_self do |node|
      annotations = source.annotations(block: node)
      refute_nil annotations.var_types[:x]
      assert_nil annotations.var_types[:y]
    end
  end

  def test_postfix_if
    source = parse_source(<<-EOF)
x + 1 if foo
y + "foo" unless bar
    EOF

    source.annotations(block: source.node)
  end

  def test_while
    source = parse_source(<<-EOF)
while foo
  # @type var x: Integer
  x.foo
end
    EOF

    source.node.yield_self do |node|
      annotations = source.annotations(block: node)
      assert_nil annotations.var_types[:x]
    end

    source.node.children[1].yield_self do |node|
      annotations = source.annotations(block: node)
      refute_nil annotations.var_types[:x]
    end
  end

  def test_until
    source = parse_source(<<-EOF)
until foo
  # @type var x: Integer
  x.foo
end
    EOF

    source.node.yield_self do |node|
      annotations = source.annotations(block: node)
      assert_nil annotations.var_types[:x]
    end

    source.node.children[1].yield_self do |node|
      annotations = source.annotations(block: node)
      refute_nil annotations.var_types[:x]
    end
  end

  def test_postfix_while_until
    source = parse_source(<<-EOF)
x + 1 while foo
y + "foo" until bar
    EOF

    source.annotations(block: source.node)
  end

  def test_post_while
    source = parse_source(<<-EOF)
begin
  # @type var x: Integer
  x.foo
x.bar
end while foo()
    EOF

    source.node.yield_self do |node|
      annotations = source.annotations(block: node)
      assert_nil annotations.var_types[:x]
    end

    source.node.children[1].yield_self do |node|
      annotations = source.annotations(block: node)
      refute_nil annotations.var_types[:x]
    end
  end

  def test_post_until
    source = parse_source(<<-EOF)
begin
  # @type var x: Integer
  x.foo
x.bar
end until foo()
    EOF

    source.node.yield_self do |node|
      annotations = source.annotations(block: node)
      assert_nil annotations.var_types[:x]
    end

    source.node.children[1].yield_self do |node|
      annotations = source.annotations(block: node)
      refute_nil annotations.var_types[:x]
    end
  end

  def test_case
    source = parse_source(<<-EOF)
case foo
when bar
  # @type var x: String
  x+1
else
  # @type var y: Integer
  y - 1
end
    EOF

    source.node.yield_self do |node|
      annotations = source.annotations(block: node)
      assert_nil annotations.var_types[:x]
      assert_nil annotations.var_types[:y]
    end

    source.node.children[1].children.last.yield_self do |node|
      annotations = source.annotations(block: node)
      refute_nil annotations.var_types[:x]
      assert_nil annotations.var_types[:y]
    end

    source.node.children[2].yield_self do |node|
      annotations = source.annotations(block: node)
      assert_nil annotations.var_types[:x]
      refute_nil annotations.var_types[:y]
    end
  end

  def test_rescue
    source = parse_source(<<-EOF)
begin
 foo
rescue Z => x
  # @type var x: String
  x+1
else
  # @type var y: Integer
  y - 1
end
    EOF

    source.node.yield_self do |node|
      annotations = source.annotations(block: node)
      assert_nil annotations.var_types[:x]
      assert_nil annotations.var_types[:y]
    end

    source.node.children[0].children[1].yield_self do |node|
      annotations = source.annotations(block: node)
      refute_nil annotations.var_types[:x]
      assert_nil annotations.var_types[:y]
    end

    source.node.children[0].children.last.yield_self do |node|
      annotations = source.annotations(block: node)
      assert_nil annotations.var_types[:x]
      refute_nil annotations.var_types[:y]
    end
  end

  def test_postfix_rescue
    source = parse_source(<<-EOF)
x + 1 rescue foo
    EOF

    source.annotations(block: source.node)
  end
end
