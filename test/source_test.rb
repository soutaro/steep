require "test_helper"

class SourceTest < Minitest::Test
  A = Steep::AST::Annotation
  T = Steep::AST::Types
  Namespace = Steep::AST::Namespace

  include TestHelper
  include SubtypingHelper

  def builder
    @builder ||= new_subtyping_checker.builder
  end

  def test_foo
    code = <<-EOF
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

    source = Steep::Source.parse(code, path: Pathname("foo.rb"))

    # toplevel
    source.annotations(block: source.node, builder: builder, current_module: nil).yield_self do |annotations|
      assert_any annotations do |a|
        a.is_a?(A::VarType) && a.name == :x1 && a.type == T::Any.new
      end
    end

    # module
    source.annotations(block: source.node.children[0], builder: builder, current_module: Namespace.parse("::Foo")).yield_self do |annotations|
      assert_any annotations do |a|
        a == A::VarType.new(name: :x2, type: T::Any.new)
      end
      assert_nil annotations.instance_type
      assert_nil annotations.module_type
    end

    # class

    source.annotations(block: source.node.children[0].children[1],
                       builder: builder,
                       current_module: Namespace.parse("::Foo::Bar")).yield_self do |annotations|
      assert_equal 5, annotations.size
      assert_equal parse_type("::String"), annotations.instance_type
      assert_equal parse_type("::String.class"), annotations.module_type
      assert_equal parse_type("any"), annotations.var_type(lvar: :x3)
      assert_equal "-> any", annotations.method_type(:foo).location.source
      assert_equal "() -> any", annotations.method_type(:bar).location.source
    end

    # def
    source.annotations(block: source.node.children[0].children[1].children[2].children[0],
                       builder: builder,
                       current_module: Namespace.parse("::Foo::Bar")).yield_self do |annotations|
      assert_equal 2, annotations.size
      assert_equal T::Any.new, annotations.var_type(lvar: :x4)
      assert_equal T::Any.new, annotations.return_type
    end

    # block
    source.annotations(block: source.node.children[0].children[1].children[2].children[0].children[2],
                       builder: builder,
                       current_module: Namespace.parse("::Foo::Bar")).yield_self do |annotations|
      assert_equal 2, annotations.size
      assert_equal T::Any.new, annotations.var_type(lvar: :x5)
      assert_equal parse_type("::Integer"), annotations.block_type
    end
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
      annotations = source.annotations(block: node, builder: builder, current_module: Namespace.root)
      assert_nil annotations.var_type(lvar: :x)
      assert_nil annotations.var_type(lvar: :y)
    end

    source.node.children[1].yield_self do |node|
      annotations = source.annotations(block: node, builder: builder, current_module: Namespace.root)
      refute_nil annotations.var_type(lvar: :x)
      assert_nil annotations.var_type(lvar: :y)
    end

    source.node.children[2].yield_self do |node|
      annotations = source.annotations(block: node, builder: builder, current_module: Namespace.root)
      assert_nil annotations.var_type(lvar: :x)
      refute_nil annotations.var_type(lvar: :y)
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
      annotations = source.annotations(block: node, builder: builder, current_module: Namespace.root)
      assert_nil annotations.var_type(lvar: :x)
      assert_nil annotations.var_type(lvar: :y)
    end

    source.node.children[1].yield_self do |node|
      annotations = source.annotations(block: node, builder: builder, current_module: Namespace.root)
      assert_nil annotations.var_type(lvar: :x)
      refute_nil annotations.var_type(lvar: :y)
    end

    source.node.children[2].yield_self do |node|
      annotations = source.annotations(block: node, builder: builder, current_module: Namespace.root)
      refute_nil annotations.var_type(lvar: :x)
      assert_nil annotations.var_type(lvar: :y)
    end
  end

  def test_elsif
    source = parse_source(<<-EOF)
if foo
  # @type var x: String
  x + "foo"
elsif bar
  # @type var y: Integer
  y + "foo"
end
    EOF

    source.node.yield_self do |node|
      annotations = source.annotations(block: node, builder: builder, current_module: Namespace.root)
      assert_nil annotations.var_type(lvar: :x)
      assert_nil annotations.var_type(lvar: :y)
    end

    source.node.children[1].yield_self do |node|
      annotations = source.annotations(block: node, builder: builder, current_module: Namespace.root)
      refute_nil annotations.var_type(lvar: :x)
      assert_nil annotations.var_type(lvar: :y)
    end

    source.node.children[2].children[1].yield_self do |node|
      annotations = source.annotations(block: node, builder: builder, current_module: Namespace.root)
      assert_nil annotations.var_type(lvar: :x)
      refute_nil annotations.var_type(lvar: :y)
    end
  end

  def test_postfix_if
    source = parse_source(<<-EOF)
x + 1 if foo
y + "foo" unless bar
    EOF

    source.annotations(block: source.node, builder: builder, current_module: Namespace.root)
  end

  def test_while
    source = parse_source(<<-EOF)
while foo
  # @type var x: Integer
  x.foo
end
    EOF

    source.node.yield_self do |node|
      annotations = source.annotations(block: node, builder: builder, current_module: Namespace.root)
      assert_nil annotations.var_type(lvar: :x)
    end

    source.node.children[1].yield_self do |node|
      annotations = source.annotations(block: node, builder: builder, current_module: Namespace.root)
      refute_nil annotations.var_type(lvar: :x)
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
      annotations = source.annotations(block: node, builder: builder, current_module: Namespace.root)
      assert_nil annotations.var_type(lvar: :x)
    end

    source.node.children[1].yield_self do |node|
      annotations = source.annotations(block: node, builder: builder, current_module: Namespace.root)
      refute_nil annotations.var_type(lvar: :x)
    end
  end

  def test_postfix_while_until
    source = parse_source(<<-EOF)
x + 1 while foo
y + "foo" until bar
    EOF

    source.annotations(block: source.node, builder: builder, current_module: Namespace.root)
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
      annotations = source.annotations(block: node, builder: builder, current_module: Namespace.root)
      assert_nil annotations.var_type(lvar: :x)
    end

    source.node.children[1].yield_self do |node|
      annotations = source.annotations(block: node, builder: builder, current_module: Namespace.root)
      refute_nil annotations.var_type(lvar: :x)
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
      annotations = source.annotations(block: node, builder: builder, current_module: Namespace.root)
      assert_nil annotations.var_type(lvar: :x)
    end

    source.node.children[1].yield_self do |node|
      annotations = source.annotations(block: node, builder: builder, current_module: Namespace.root)
      refute_nil annotations.var_type(lvar: :x)
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
      annotations = source.annotations(block: node, builder: builder, current_module: Namespace.root)
      assert_nil annotations.var_type(lvar: :x)
      assert_nil annotations.var_type(lvar: :y)
    end

    source.node.children[1].children.last.yield_self do |node|
      annotations = source.annotations(block: node, builder: builder, current_module: Namespace.root)
      refute_nil annotations.var_type(lvar: :x)
      assert_nil annotations.var_type(lvar: :y)
    end

    source.node.children[2].yield_self do |node|
      annotations = source.annotations(block: node, builder: builder, current_module: Namespace.root)
      assert_nil annotations.var_type(lvar: :x)
      refute_nil annotations.var_type(lvar: :y)
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
      annotations = source.annotations(block: node, builder: builder, current_module: Namespace.root)
      assert_nil annotations.var_type(lvar: :x)
      assert_nil annotations.var_type(lvar: :y)
    end

    source.node.children[0].children[1].yield_self do |node|
      annotations = source.annotations(block: node, builder: builder, current_module: Namespace.root)
      refute_nil annotations.var_type(lvar: :x)
      assert_nil annotations.var_type(lvar: :y)
    end

    source.node.children[0].children.last.yield_self do |node|
      annotations = source.annotations(block: node, builder: builder, current_module: Namespace.root)
      assert_nil annotations.var_type(lvar: :x)
      refute_nil annotations.var_type(lvar: :y)
    end
  end

  def test_postfix_rescue
    source = parse_source(<<-EOF)
x + 1 rescue foo
    EOF

    source.annotations(block: source.node, builder: builder, current_module: Namespace.root)
  end

  def test_ternary_operator
    source = parse_source(<<-EOF)
a = test() ? foo : bar
    EOF

    assert_instance_of Steep::Source, source
    source.annotations(block: source.node, builder: builder, current_module: Namespace.root)
  end

  def test_defs
    source = parse_source(<<-EOF)
class A
  def self.foo()
    # @type var x: Integer
    x = 123
  end
end
    EOF

    def_node = dig(source.node, 2)
    annotations = source.annotations(block: def_node, builder: builder, current_module: Namespace.parse("::A"))
    assert_equal parse_type("::Integer"), annotations.var_type(lvar: :x)
  end

  def test_find_node
    source = parse_source(<<-EOF)
class A
  def self.foo(bar)
    # @type var x: Integer
    x = 123
  end
end
    EOF

    assert_equal source.node, source.find_node(line: 1, column: 2)            # class
    assert_equal dig(source.node, 0), source.find_node(line: 1, column: 6)    # A
    assert_equal dig(source.node, 0), source.find_node(line: 1, column: 7)    # A
    assert_equal dig(source.node, 2, 0), source.find_node(line: 2, column: 6) # self
    assert_equal dig(source.node, 2), source.find_node(line: 2, column: 11)   # def
    assert_equal dig(source.node, 2, 2, 0), source.find_node(line: 2, column: 15)   # bar
    assert_equal dig(source.node, 2, 3), source.find_node(line: 4, column: 5)   # x
    assert_equal dig(source.node, 2, 3, 1), source.find_node(line: 4, column: 8)   # 123
    assert_equal dig(source.node, 2, 3, 1), source.find_node(line: 4, column: 9)   # 123
    assert_equal dig(source.node, 2, 3, 1), source.find_node(line: 4, column: 10)   # 123
    assert_equal dig(source.node, 2, 3, 1), source.find_node(line: 4, column: 11)   # 123
  end
end
