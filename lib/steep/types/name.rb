module Steep
  module Types
    class Name
      attr_reader :name

      def initialize(name:)
        @name = name
      end

      def ==(other)
        other.is_a?(Name) && name == other.name
      end

      def hash
        name.hash
      end
    end
  end
end
