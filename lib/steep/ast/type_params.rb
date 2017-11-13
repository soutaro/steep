module Steep
  module AST
    class TypeParams
      attr_reader :location
      attr_reader :variables

      def initialize(location: nil, variables:)
        @location = location
        @variables = variables
      end
    end
  end
end
