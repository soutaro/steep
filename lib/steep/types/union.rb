module Steep
  module Types
    class Union
      attr_reader :types

      def initialize(types:)
        @types = types
      end

      def ==(other)
        other.is_a?(Union) && other.types.sort_by {|x| x.__id__ } == types.sort_by {|x| x.__id__ }
      end

      def hash
        types.hash
      end

      def eql?(other)
        self == other
      end

      def closed?
        types.all? {|x| x.closed? }
      end

      def substitute(klass:, instance:, params:)
        self.class.new(types: types.map {|t| t.substitute(klass: klass, instance: instance, params: params) })
      end

      def to_s
        types.join(" | ")
      end
    end
  end
end
