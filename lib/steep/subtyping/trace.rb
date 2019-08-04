module Steep
  module Subtyping
    class Trace
      attr_reader :array

      def initialize(array: [])
        @array = array
      end

      def interface(sub, sup, &block)
        push :interface, sub, sup, &block
      end

      def method(name, sub, sup, &block)
        push :method, sub, sup, name, &block
      end

      def method_type(name, sub, sup, &block)
        push :method_type, sub, sup, name, &block
      end

      def type(sub, sup, &block)
        push :type, sub, sup, &block
      end

      def push(*xs)
        array << xs
        yield
      ensure
        array.pop
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
            yield(*pair)
          end
        else
          enum_for :each
        end
      end
    end
  end
end
