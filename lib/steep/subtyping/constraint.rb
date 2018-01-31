module Steep
  module Subtyping
    class Constraint
      attr_reader :sub_type
      attr_reader :super_type

      def initialize(sub_type:, super_type:)
        @sub_type = sub_type
        @super_type = super_type
      end

      def hash
        self.class.hash ^ sub_type.hash ^ super_type.hash
      end

      def ==(other)
        other.is_a?(self.class) && other.sub_type == sub_type && other.super_type == super_type
      end

      alias eql? ==

      def to_s
        "#{sub_type} <: #{super_type}"
      end

      def map
        self.class.new(
          sub_type: yield(sub_type),
          super_type: yield(super_type)
        )
      end
    end
  end
end
