require "test_helper"

class ContextArrayTest < Minitest::Test
  include Minitest::Hooks
  include TestHelper
  include FactoryHelper

  ContextArray = Steep::TypeInference::ContextArray

  def test_array
    with_factory do
      source = parse_ruby(<<EOF)
foo { }
bar do |x|
  foo
end
EOF

      array = ContextArray.from_source(source: source)

      assert_nil array[0]

      array.insert_context(5..6, context: :context1)

      array.insert_context(
        dig(source.node, 1, 1).loc.end.end_pos..dig(source.node, 1).loc.end.begin_pos,
        context: :context2
      )

      assert_nil array[4]
      assert_equal :context1, array[5]
      assert_equal :context1, array[6]
      assert_nil array[7]

      assert_nil array.at(line: 1, column: 4)
      assert_equal :context1, array.at(line: 1, column: 5)
      assert_equal :context1, array.at(line: 1, column: 6)
      assert_nil array.at(line: 1, column: 7)

      assert_nil array.at(line: 2, column: 9)
      assert_equal :context2, array.at(line: 2, column: 10)
      assert_equal :context2, array.at(line: 3, column: 3)
      assert_equal :context2, array.at(line: 4, column: 0)
      assert_nil array.at(line: 4, column: 1)

      assert_nil array.at(line: 4, column: 3)
    end
  end

  def test_subtree_and_range
    with_factory do
      source = parse_ruby(<<EOF)
foo { }
bar do |x|
  foo
end
EOF

      array = ContextArray.from_source(source: source)

      range2 = dig(source.node, 1, 1).loc.end.end_pos..dig(source.node, 1).loc.end.begin_pos
      range3 = dig(source.node, 1, 2).yield_self {|n| n.loc.expression.begin_pos..n.loc.expression.end_pos }

      array.insert_context(range2, context: :context2)

      assert_equal :context2, array[range2.begin]
      assert_equal :context2, array[range2.end]
      assert_equal :context2, array[range3.begin]
      assert_equal :context2, array[range3.end]

      ContextArray.new(buffer: array.buffer, range: range2).tap do |sub|
        sub.insert_context(range3, context: :context3)

        assert_nil sub[range2.begin]
        assert_nil sub[range2.end]
        assert_equal :context3, sub[range3.begin]
        assert_equal :context3, sub[range3.end]

        array.merge(sub)
      end

      assert_equal :context2, array[range2.begin]
      assert_equal :context3, array[range3.begin]
      assert_equal :context3, array[range3.end]
      assert_equal :context2, array[range2.end]
    end
  end
end
