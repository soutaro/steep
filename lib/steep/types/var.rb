module Steep
  module Types
    class Var
      # @implements Steep__Types__Var

      attr_reader :name

      def initialize(name:)
        @name = name
      end

      def ==(other)
        other.is_a?(Var) && other.name == name
      end

      def hash
        name.hash
      end

      def eql?(other)
        self == other
      end

      def closed?
        true
      end

      def substitute(klass:, instance:, params:)
        params[name] || self
      end

      def to_s
        "'#{name}"
      end
    end
  end
end
