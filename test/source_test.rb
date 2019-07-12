require "test_helper"

class SourceTest < Minitest::Test
  A = Steep::AST::Annotation
  T = Steep::AST::Types
  Namespace = Steep::AST::Namespace

  include TestHelper
  include SubtypingHelper
  include FactoryHelper

  def test_foo
    with_factory do |factory|
      code = <<-EOF
# @type var x1: any

module Foo
  # @type var x2: any

  class Bar
    # @type instance: String
    # @type module: singleton(String)

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

      source = Steep::Source.parse(code, path: Pathname("foo.rb"), factory: factory)

      # toplevel
      source.annotations(block: source.node,
                         factory: factory,
                         current_module: nil).yield_self do |annotations|
        assert_any annotations do |a|
          a.is_a?(A::VarType) && a.name == :x1 && a.type == T::Any.new
        end
      end

      # module
      source.annotations(block: dig(source.node, 0),
                         factory: factory,
                         current_module: Namespace.parse("::Foo")).yield_self do |annotations|
        assert_any annotations do |a|
          a == A::VarType.new(name: :x2, type: T::Any.new)
        end
        assert_nil annotations.instance_type
        assert_nil annotations.module_type
      end

      # class

      source.annotations(block: dig(source.node, 0, 1),
                         factory: factory,
                         current_module: Namespace.parse("::Foo::Bar")).yield_self do |annotations|
        assert_equal 5, annotations.size
        assert_equal parse_type("::String"), annotations.instance_type
        assert_equal parse_type("singleton(::String)"), annotations.module_type
        assert_equal parse_type("any"), annotations.var_type(lvar: :x3)
      end

      # def
      source.annotations(block: dig(source.node, 0, 1, 2, 0),
                         factory: factory,
                         current_module: Namespace.parse("::Foo::Bar")).yield_self do |annotations|
        assert_equal 2, annotations.size
        assert_equal T::Any.new, annotations.var_type(lvar: :x4)
        assert_equal T::Any.new, annotations.return_type
      end

      # block
      source.annotations(block: dig(source.node, 0, 1, 2, 0, 2),
                         factory: factory,
                         current_module: Namespace.parse("::Foo::Bar")).yield_self do |annotations|
        assert_equal 2, annotations.size
        assert_equal T::Any.new, annotations.var_type(lvar: :x5)
        assert_equal parse_type("::Integer"), annotations.block_type
      end
    end
  end

  def test_if
    with_factory do |factory|
      code = <<-EOF
if foo
  # @type var x: String
  x + "foo"
else
  # @type var y: Integer
  y + "foo"
end
      EOF
      source = Steep::Source.parse(code, path: Pathname("foo.rb"), factory: factory)

      source.node.yield_self do |node|
        annotations = source.annotations(block: node, factory: factory, current_module: Namespace.root)
        assert_nil annotations.var_type(lvar: :x)
        assert_nil annotations.var_type(lvar: :y)
      end

      source.node.children[1].yield_self do |node|
        annotations = source.annotations(block: node, factory: factory, current_module: Namespace.root)
        refute_nil annotations.var_type(lvar: :x)
        assert_nil annotations.var_type(lvar: :y)
      end

      source.node.children[2].yield_self do |node|
        annotations = source.annotations(block: node, factory: factory, current_module: Namespace.root)
        assert_nil annotations.var_type(lvar: :x)
        refute_nil annotations.var_type(lvar: :y)
      end
    end
  end

  def test_unless
    with_factory do |factory|
      source = Steep::Source.parse(<<-EOF, path: Pathname("foo.rb"), factory: factory)
unless foo then
  # @type var x: Integer
  x + 1
else
  # @type var y: String
  y + "foo"
end
      EOF

      source.node.yield_self do |node|
        annotations = source.annotations(block: node, factory: factory, current_module: Namespace.root)
        assert_nil annotations.var_type(lvar: :x)
        assert_nil annotations.var_type(lvar: :y)
      end

      source.node.children[1].yield_self do |node|
        annotations = source.annotations(block: node, factory: factory, current_module: Namespace.root)
        assert_nil annotations.var_type(lvar: :x)
        refute_nil annotations.var_type(lvar: :y)
      end

      source.node.children[2].yield_self do |node|
        annotations = source.annotations(block: node, factory: factory, current_module: Namespace.root)
        refute_nil annotations.var_type(lvar: :x)
        assert_nil annotations.var_type(lvar: :y)
      end
    end
  end

  def test_elsif
    with_factory do |factory|
      source = Steep::Source.parse(<<-EOF, path: Pathname("foo.rb"), factory: factory)
if foo
  # @type var x: String
  x + "foo"
elsif bar
  # @type var y: Integer
  y + "foo"
end
      EOF

      source.node.yield_self do |node|
        annotations = source.annotations(block: node, factory: factory, current_module: Namespace.root)
        assert_nil annotations.var_type(lvar: :x)
        assert_nil annotations.var_type(lvar: :y)
      end

      dig(source.node, 1).yield_self do |node|
        annotations = source.annotations(block: node, factory: factory, current_module: Namespace.root)
        refute_nil annotations.var_type(lvar: :x)
        assert_nil annotations.var_type(lvar: :y)
      end

      dig(source.node, 2, 1).yield_self do |node|
        annotations = source.annotations(block: node, factory: factory, current_module: Namespace.root)
        assert_nil annotations.var_type(lvar: :x)
        refute_nil annotations.var_type(lvar: :y)
      end
    end
  end

  def test_postfix_if
    with_factory do |factory|
      source = Steep::Source.parse(<<-EOF, path: Pathname("foo.rb"), factory: factory)
x + 1 if foo
y + "foo" unless bar
      EOF

      source.annotations(block: source.node, factory: factory, current_module: Namespace.root)
    end
  end

  def test_while
    with_factory do |factory|
      source = Steep::Source.parse(<<-EOF, path: Pathname("foo.rb"), factory: factory)
while foo
  # @type var x: Integer
  x.foo
end
      EOF
      source.node.yield_self do |node|
        annotations = source.annotations(block: node, factory: factory, current_module: Namespace.root)
        assert_nil annotations.var_type(lvar: :x)
      end

      source.node.children[1].yield_self do |node|
        annotations = source.annotations(block: node, factory: factory, current_module: Namespace.root)
        refute_nil annotations.var_type(lvar: :x)
      end
    end
  end

  def test_until
    with_factory do |factory|
      source = Steep::Source.parse(<<-EOF, path: Pathname("foo.rb"), factory: factory)
until foo
  # @type var x: Integer
  x.foo
end
      EOF

      source.node.yield_self do |node|
        annotations = source.annotations(block: node, factory: factory, current_module: Namespace.root)
        assert_nil annotations.var_type(lvar: :x)
      end

      source.node.children[1].yield_self do |node|
        annotations = source.annotations(block: node, factory: factory, current_module: Namespace.root)
        refute_nil annotations.var_type(lvar: :x)
      end
    end
  end

  def test_postfix_while_until
    with_factory do |factory|
      source = Steep::Source.parse(<<-EOF, path: Pathname("foo.rb"), factory: factory)
x + 1 while foo
y + "foo" until bar
      EOF

      source.annotations(block: source.node, factory: factory, current_module: Namespace.root)
    end
  end

  def test_post_while
    with_factory do |factory|
      source = Steep::Source.parse(<<-EOF, path: Pathname("foo.rb"), factory: factory)
begin
  # @type var x: Integer
  x.foo
x.bar
end while foo()
      EOF

      source.node.yield_self do |node|
        annotations = source.annotations(block: node, factory: factory, current_module: Namespace.root)
        assert_nil annotations.var_type(lvar: :x)
      end

      source.node.children[1].yield_self do |node|
        annotations = source.annotations(block: node, factory: factory, current_module: Namespace.root)
        refute_nil annotations.var_type(lvar: :x)
      end
    end
  end

  def test_post_until
    with_factory do |factory|
      source = Steep::Source.parse(<<-EOF, path: Pathname("foo.rb"), factory: factory)
begin
  # @type var x: Integer
  x.foo
x.bar
end until foo()
      EOF

      source.node.yield_self do |node|
        annotations = source.annotations(block: node, factory: factory, current_module: Namespace.root)
        assert_nil annotations.var_type(lvar: :x)
      end

      source.node.children[1].yield_self do |node|
        annotations = source.annotations(block: node, factory: factory, current_module: Namespace.root)
        refute_nil annotations.var_type(lvar: :x)
      end
    end
  end

  def test_case
    with_factory do |factory|
      source = Steep::Source.parse(<<-EOF, path: Pathname("foo.rb"), factory: factory)
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
        annotations = source.annotations(block: node, factory: factory, current_module: Namespace.root)
        assert_nil annotations.var_type(lvar: :x)
        assert_nil annotations.var_type(lvar: :y)
      end

      source.node.children[1].children.last.yield_self do |node|
        annotations = source.annotations(block: node, factory: factory, current_module: Namespace.root)
        refute_nil annotations.var_type(lvar: :x)
        assert_nil annotations.var_type(lvar: :y)
      end

      source.node.children[2].yield_self do |node|
        annotations = source.annotations(block: node, factory: factory, current_module: Namespace.root)
        assert_nil annotations.var_type(lvar: :x)
        refute_nil annotations.var_type(lvar: :y)
      end
    end
  end

  def test_rescue
    with_factory do |factory|
      source = Steep::Source.parse(<<-EOF, path: Pathname("foo.rb"), factory: factory)
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
        annotations = source.annotations(block: node, factory: factory, current_module: Namespace.root)
        assert_nil annotations.var_type(lvar: :x)
        assert_nil annotations.var_type(lvar: :y)
      end

      source.node.children[0].children[1].yield_self do |node|
        annotations = source.annotations(block: node, factory: factory, current_module: Namespace.root)
        refute_nil annotations.var_type(lvar: :x)
        assert_nil annotations.var_type(lvar: :y)
      end

      source.node.children[0].children.last.yield_self do |node|
        annotations = source.annotations(block: node, factory: factory, current_module: Namespace.root)
        assert_nil annotations.var_type(lvar: :x)
        refute_nil annotations.var_type(lvar: :y)
      end
    end
  end

  def test_postfix_rescue
    with_factory do |factory|
      source = Steep::Source.parse(<<-EOF, path: Pathname("foo.rb"), factory: factory)
x + 1 rescue foo
    EOF

      source.annotations(block: source.node, factory: factory, current_module: Namespace.root)
    end
  end

  def test_ternary_operator
    with_factory do |factory|
      source = Steep::Source.parse(<<-EOF, path: Pathname("foo.rb"), factory: factory)
a = test() ? foo : bar
      EOF

      source.annotations(block: source.node, factory: factory, current_module: Namespace.root)
    end
  end

  def test_defs
    with_factory do |factory|
      source = Steep::Source.parse(<<-EOF, path: Pathname("foo.rb"), factory: factory)
class A
  def self.foo()
    # @type var x: Integer
    x = 123
  end
end
      EOF
      def_node = dig(source.node, 2)

      annotations = source.annotations(block: def_node, factory: factory, current_module: Namespace.parse("::A"))
      assert_equal parse_type("::Integer"), annotations.var_type(lvar: :x)
    end
  end

  def test_find_node
    with_factory do |factory|
      source = Steep::Source.parse(<<-EOF, path: Pathname("foo.rb"), factory: factory)
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
end
