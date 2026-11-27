require_relative "test_helper"

class NodeHelperTest < Minitest::Test
  include Steep
  include TestHelper
  include FactoryHelper

  # `NodeHelper` has `test_*` methods, which are run as tests if the module is included in the test class
  class Helper
    include Steep::NodeHelper
  end

  # Returns the sources of the `break` and `next` nodes that jump from the block of the first line
  def jump_sources(ruby)
    with_factory do |factory|
      source = parse_ruby(ruby, factory: factory)
      node = source.node or raise
      node.type == :block or raise
      body = node.children[2] or raise

      Helper.new.each_jump_node(body).map { _1.location.expression.source }
    end
  end

  def test_each_jump_node
    assert_equal ["break 1", "next 2", "break"], jump_sources(<<~RUBY)
      foo do
        break 1 if bar
        begin
          next 2
        rescue
          break
        end
      end
    RUBY
  end

  def test_each_jump_node__single
    assert_equal ["break 1"], jump_sources("foo { break 1 }")
  end

  def test_each_jump_node__nested_block
    # The receiver and the arguments of the nested block call are type checked with the outer block
    assert_equal ["break 1", "next 2"], jump_sources(<<~RUBY)
      foo do
        bar((break 1 if baz)) { break :inner }
        -> { next :inner }
        baz { _1 or break :inner }
        baz { it or break :inner }
        next 2
      end
    RUBY
  end

  def test_each_jump_node__loop
    # The condition of the loop is type checked with the outer block
    assert_equal ["break 1", "next 2"], jump_sources(<<~RUBY)
      foo do
        while (break 1 if bar; baz)
          break :inner
        end
        until bar
          next :inner
        end
        begin
          break :inner
        end while bar
        begin
          break :inner
        end until bar
        next 2
      end
    RUBY
  end

  def test_each_jump_node__for
    # The collection of the loop is type checked with the outer block
    assert_equal ["break 1", "next 2"], jump_sources(<<~RUBY)
      foo do
        for x in (break 1 if bar; baz)
          break :inner
        end
        next 2
      end
    RUBY
  end

  def test_each_jump_node__definition
    assert_equal ["break 1"], jump_sources(<<~RUBY)
      foo do
        def bar = (break :inner)
        def self.baz = (break :inner)
        class Foo
          break :inner
        end
        module Bar
          break :inner
        end
        class << self
          break :inner
        end
        break 1
      end
    RUBY
  end

  def test_each_jump_node__value
    assert_equal ["break (next 1 if foo; 2)", "next 1"], jump_sources(<<~RUBY)
      foo do
        break (next 1 if foo; 2)
      end
    RUBY
  end
end
