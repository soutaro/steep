module Steep
  module Types
    class Class
      def ==(other)
        other.is_a?(Class)
      end

      def hash
        self.class.hash
      end

      def eql?(other)
        self == other
      end

      def closed?
        false
      end

      def substitute(klass:, instance:, params:)
        klass
      end
    end
  end
end
