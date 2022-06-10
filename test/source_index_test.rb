require_relative "test_helper"

class SourceIndexTest < Minitest::Test
  include TestHelper
  include FactoryHelper
  include TypeConstructionHelper
  include SubtypingHelper

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

      index.add_definition(constant: TypeName("::Foo"), definition: dig(source.node, 0, 0))

      assert_equal 1, index.count

      child = index.new_child

      assert_equal 1, child.count

      child.add_definition(constant: TypeName("::Bar"), definition: dig(source.node, 1, 0))

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

      index.add_definition(constant: TypeName("::Foo"), definition: dig(source.node, 0, 0))

      assert_raises do
        index.merge!(child)
      end
    end
  end

  def test_constant_index
    with_checker <<-EOF do |checker|
class Foo
end

module Bar
end

Foo::VERSION: String
    EOF

      source = parse_ruby(<<-'RUBY')
class Foo
  VERSION = "0.1.1"

  module ::Bar
  end
end

      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_instance_of SourceIndex, typing.source_index

        typing.source_index.constant_index[TypeName("::Foo")].tap do |entry|
          assert_equal Set[dig(source.node, 0)].compare_by_identity, entry.definitions
          assert_empty entry.references
        end

        typing.source_index.constant_index[TypeName("::Bar")].tap do |entry|
          assert_equal Set[dig(source.node, 2, 1, 0)].compare_by_identity, entry.definitions
          assert_empty entry.references
        end

        typing.source_index.constant_index[TypeName("::Foo::VERSION")].tap do |entry|
          assert_equal Set[dig(source.node, 2, 0)].compare_by_identity, entry.definitions
          assert_empty entry.references
        end
      end
    end
  end

  def test_def_index
    with_checker <<-EOF do |checker|
class DefIndex
  def f: () -> void

  def self.g: () -> void
end
    EOF

      source = parse_ruby(<<-'RUBY')
class DefIndex
  def f()
  end

  def self.g()
  end
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_instance_of SourceIndex, typing.source_index

        typing.source_index.method_index[MethodName("::DefIndex#f")].tap do |entry|
          assert_equal Set[dig(source.node, 2, 0)].compare_by_identity, entry.definitions
          assert_empty entry.references
        end

        typing.source_index.method_index[MethodName("::DefIndex.g")].tap do |entry|
          assert_equal Set[dig(source.node, 2, 1)].compare_by_identity, entry.definitions
          assert_empty entry.references
        end
      end
    end
  end
end
