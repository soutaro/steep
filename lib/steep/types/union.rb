module Steep
  module Types
    class Union
      attr_reader :types

      def initialize(types:)
        @types = types
      end

      def ==(other)
        other.is_a?(Union) && other.types == types
      end

      def hash
        types.hash
      end

      def closed?
        types.all?(&:closed?)
      end

      def substitute(klass:, instance:, params:)
        self.class.new(types: types.map {|t| t.substitute(klass: klass, instance: instance, params: params) })
      end
    end
  end
end
