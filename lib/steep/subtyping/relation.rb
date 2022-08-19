module Steep
  module Subtyping
    class Relation
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

      def to_ary
        [sub_type, super_type]
      end

      def type?
        !interface? && !method? && !function? && !params? && !block?
      end

      def interface?
        sub_type.is_a?(Interface::Shape) && super_type.is_a?(Interface::Shape)
      end

      def method?
        (sub_type.is_a?(Interface::Shape::Entry) || sub_type.is_a?(Interface::MethodType)) &&
          (super_type.is_a?(Interface::Shape::Entry) || super_type.is_a?(Interface::MethodType))
      end

      def function?
        sub_type.is_a?(Interface::Function) && super_type.is_a?(Interface::Function)
      end

      def params?
        sub_type.is_a?(Interface::Function::Params) && super_type.is_a?(Interface::Function::Params)
      end

      def block?
        (sub_type.is_a?(Interface::Block) || !sub_type) &&
          (!super_type || super_type.is_a?(Interface::Block))
      end

      def assert_type(type)
        unless __send__(:"#{type}?")
          raise "#{type}? is expected but: sub_type=#{sub_type.class}, super_type=#{super_type.class}"
        end
      end

      def type!
        assert_type(:type)
      end

      def interface!
        assert_type(:interface)
      end

      def method!
        assert_type(:method)
      end

      def function!
        assert_type(:function)
      end

      def params!
        assert_type(:params)
      end

      def block!
        assert_type(:block)
      end

      def map
        self.class.new(
          sub_type: yield(sub_type),
          super_type: yield(super_type)
        )
      end

      def flip
        self.class.new(
          sub_type: super_type,
          super_type: sub_type
        )
      end
    end
  end
end
