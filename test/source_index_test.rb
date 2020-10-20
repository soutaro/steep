require "test_helper"

class SourceIndexTest < Minitest::Test
  include TestHelper
  include FactoryHelper

  SourceIndex = Steep::Index::SourceIndex

  def test_nested_index
    with_factory do
      source = parse_ruby(<<RUBY)
class Foo
end

module Bar
end
RUBY

      index = SourceIndex.new(source: source)

      assert_equal 0, index.count

      index.add_definition(constant: TypeName("::Foo"), definition: dig(source.node, 0))

      assert_equal 1, index.count

      child = index.new_child

      assert_equal 1, child.count

      child.add_definition(constant: TypeName("::Bar"), definition: dig(source.node, 1))

      assert_equal 1, index.count
      assert_equal 2, child.count

      index.merge!(child)

      assert_equal 3, index.count
    end
  end

  def test_nested_index_error
    with_factory do
      source = parse_ruby(<<RUBY)
class Foo
end

module Bar
end
RUBY

      index = SourceIndex.new(source: source)
      child = index.new_child

      index.add_definition(constant: TypeName("::Foo"), definition: dig(source.node, 0))

      assert_raises do
        index.merge!(child)
      end
    end
  end
end
