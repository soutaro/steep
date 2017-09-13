module Steep
  module Types
    class Merge
      # @implements Steep__Types__Merge

      # @dynamic types
      attr_reader :types

      def initialize(types:)
        @types = types
      end

      def ==(other)
        # @type var other_: Steep__Types__Merge
        other_ = other
        other_.is_a?(Merge) && other_.types == types
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
