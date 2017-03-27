module Steep
  module Types
    class Any
      def ==(other)
        other.is_a?(Any)
      end

      def hash
        self.class.hash
      end
    end
  end
end
