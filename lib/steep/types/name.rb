module Steep
  module Types
    class Name
      attr_reader :name
      attr_reader :params

      def initialize(name:, params:)
        @name = name
        @params = params
      end

      def ==(other)
        other.is_a?(Name) && name == other.name && other.params == params
      end

      def hash
        name.hash ^ params.hash
      end
    end
  end
end
