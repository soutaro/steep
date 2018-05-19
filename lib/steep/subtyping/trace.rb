module Steep
  module Subtyping
    class Trace
      attr_reader :array

      def initialize(array: [])
        @array = array
      end

      def add(sup, sub)
        array << [sup, sub]
        yield
      ensure
        array.pop
      end

      def empty?
        array.empty?
      end

      def drop(n)
        self.class.new(array: array.drop(n))
      end

      def size
        array.size
      end

      def +(other)
        self.class.new(array: array + other.array)
      end

      def initialize_copy(source)
        @array = source.array.dup
      end

      def each
        if block_given?
          array.each do |pair|
            yield *pair
          end
        else
          enum_for :each
        end
      end
    end
  end
end
