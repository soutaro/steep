require "test_helper"

class ShimTest < Minitest::Test
  def test_filter_map
    klass = Class.new do
      include Shims::EnumerableFilterMap

      def each(&block)
        10.times(&block)
      end
    end

    assert_equal %w(0 2 4 6 8), klass.new.each.filter_map {|i| i.even? && i.to_s }
  end
end
