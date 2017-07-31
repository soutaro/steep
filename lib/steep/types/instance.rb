module Steep
  module Types
    class Instance
      def ==(other)
        other.is_a?(Instance)
      end

      def eql?(other)
        self == other
      end

      def hash
        self.class.hash
      end
    end
  end
end
