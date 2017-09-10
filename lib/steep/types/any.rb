module Steep
  module Types
    class Any
      # @implements Steep__Types__Any

      def ==(other)
        other.is_a?(Any)
      end

      def hash
        self.class.hash
      end

      def eql?(other)
        other == self
      end

      def closed?
        true
      end

      def substitute(klass:, instance:, params:)
        self
      end

      def to_s
        "any"
      end
    end
  end
end
