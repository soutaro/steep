module Steep
  module Types
    class Merge
      attr_reader :types

      def initialize(types:)
        @types = types
      end

      def ==(other)
        other.is_a?(Merge) && other.types == types
      end

      def hash
        self.class.hash ^ types.hash
      end

      def eql?(other)
        other == self
      end

      def to_s
        types.join(" + ")
      end
    end
  end
end
