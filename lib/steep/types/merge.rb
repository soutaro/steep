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

      def to_s
        types.join(" + ")
      end
    end
  end
end
