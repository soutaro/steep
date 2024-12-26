require_relative "test_helper"

class IndexTest < Minitest::Test
  include TestHelper
  include FactoryHelper
  include SubtypingHelper
  include TypeConstructionHelper

  RBSIndex = Steep::Index::RBSIndex
  SourceIndex = Steep::Index::SourceIndex

  def assert_node_set(nodes, *locs)
    node_locations = Set.new(
      nodes.map do |node|
        [
          [node.location.first_line, node.location.column],
          [node.location.last_line, node.location.last_column]
        ]
      end
    )

    assert_equal Set.new(locs), node_locations
  end

  def test_class
    with_checker(<<-RBS) do |checker|
class HelloWorld
end
    RBS
      source = parse_ruby(<<-RUBY)
class HelloWorld < String
end

HelloWorld.new()
::HelloWorld.new()
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)
        assert_no_error typing

        typing.source_index.entry(constant: RBS::TypeName.parse("::HelloWorld")).tap do |entry|
          assert_instance_of SourceIndex::ConstantEntry, entry

          assert_node_set entry.definitions,
                          [[1, 6], [1, 16]]

          assert_node_set entry.references,
                          [[4, 0], [4, 10]],
                          [[5, 0], [5, 12]]
        end

        typing.source_index.entry(constant: RBS::TypeName.parse("::String")).tap do |entry|
          assert_instance_of SourceIndex::ConstantEntry, entry

          assert_node_set entry.definitions

          assert_node_set entry.references,
                          [[1, 19], [1, 25]]
        end
      end
    end
  end

  def test_module
    with_checker(<<-RBS) do |checker|
module HelloWorld
end
    RBS
      source = parse_ruby(<<-RUBY)
module HelloWorld
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)
        assert_no_error typing

        typing.source_index.entry(constant: RBS::TypeName.parse("::HelloWorld")).tap do |entry|
          assert_instance_of SourceIndex::ConstantEntry, entry

          assert_node_set entry.definitions,
                          [[1, 7], [1, 17]]
        end
      end
    end
  end

  def test_cdecl
    with_checker(<<-RBS) do |checker|
module HelloWorld
  VERSION: String
end
    RBS
      source = parse_ruby(<<-RUBY)
module HelloWorld
  VERSION = "1.2.3"

  puts VERSION
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)
        assert_no_error typing

        typing.source_index.entry(constant: RBS::TypeName.parse("::HelloWorld::VERSION")).tap do |entry|
          assert_instance_of SourceIndex::ConstantEntry, entry

          assert_node_set entry.definitions,
                          [[2, 2], [2, 19]]

          assert_node_set entry.references,
                          [[4, 7], [4, 14]]
        end
      end
    end
  end
end
