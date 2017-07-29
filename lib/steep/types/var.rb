module Steep
  module Types
    class Var
      attr_reader :name

      def initialize(name:)
        @name = name
      end

      def ==(other)
        other.is_a?(Var) && other.name == name
      end

      def hash
        name.hash
      end
    end
  end
end
