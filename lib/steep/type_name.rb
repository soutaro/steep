module Steep
  module TypeName
    class Interface
      attr_reader :name

      def initialize(name:)
        @name = name
      end

      def ==(other)
        other.is_a?(self.class) && other.name == name
      end

      def hash
        name.hash
      end

      def eql?(other)
        self == other
      end
    end
  end
end
