module Steep
  module Types
    class Any
      def ==(other)
        other.is_a?(Any)
      end

      def hash
        self.class.hash
      end

      def closed?
        true
      end

      def substitute(klass:, instance:, params:)
        self
      end
    end
  end
end
