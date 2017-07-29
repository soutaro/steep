module Steep
  module Types
    class Union
      attr_reader :types

      def initialize(types:)
        @types = types
      end

      def ==(other)
        other.is_a?(Union) && other.types == types
      end

      def hash
        types.hash
      end
    end
  end
end
