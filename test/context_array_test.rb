require "test_helper"

class ContextArrayTest < Minitest::Test
  include Minitest::Hooks
  include TestHelper
  include FactoryHelper

  ContextArray = Steep::TypeInference::ContextArray
  AST = Steep::AST

  def dump(array, entry = array.root, prefix: "")
    puts "#{prefix}#{entry.range} => #{entry.context}"
    entry.sub_entries.each do |sub|
      dump array, sub, prefix: "#{prefix}  "
    end
  end

  def test_array_1
    with_factory do
      buffer = AST::Buffer.new(name: :buf, content: <<EOF)
01234567890123456789
EOF

      array = ContextArray.new(buffer: buffer, context: :root)
      array.insert_context 1..10, context: :context1
      array.insert_context 5..8, context: :context2
      array.insert_context 3..8, context: :context3

      assert_equal :root, array[0]
      assert_equal :root, array[11]
      assert_equal :context1, array[1]
      assert_equal :context1, array[10]
      assert_equal :context2, array[5]
      assert_equal :context2, array[8]
      assert_equal :context3, array[3]
    end
  end

  def test_array_2
    with_factory do
      buffer = AST::Buffer.new(name: :buf, content: <<EOF)
01234567890123456789
EOF

      array = ContextArray.new(buffer: buffer, context: :root)
      array.insert_context 1..5, context: :context1
      array.insert_context 5..8, context: :context2

      assert_equal :context1, array[5]
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

      ContextArray.new(buffer: array.buffer, range: range2, context: nil).tap do |sub|
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
