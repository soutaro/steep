module Steep
  module Interface
    class Instantiated
      attr_reader :type
      attr_reader :methods

      def initialize(type:, methods:)
        @type = type
        @methods = methods
      end

      def ==(other)
        other.is_a?(self.class) && other.type == type && other.params == params && other.methods == methods
      end
    end
  end
end
