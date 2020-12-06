module Steep
  module Interface
    class Block
      attr_reader :type
      attr_reader :optional

      def initialize(type:, optional:)
        @type = type
        @optional = optional
      end

      def optional?
        @optional
      end

      def to_optional
        self.class.new(
          type: type,
          optional: true
        )
      end

      def ==(other)
        other.is_a?(self.class) && other.type == type && other.optional == optional
      end

      alias eql? ==

      def hash
        type.hash ^ optional.hash
      end

      def closed?
        type.closed?
      end

      def subst(s)
        ty = type.subst(s)
        if ty == type
          self
        else
          self.class.new(
            type: ty,
            optional: optional
          )
        end
      end

      def free_variables()
        @fvs ||= type.free_variables
      end

      def to_s
        "#{optional? ? "?" : ""}{ #{type.params} -> #{type.return_type} }"
      end

      def map_type(&block)
        self.class.new(
          type: type.map_type(&block),
          optional: optional
        )
      end

      def +(other)
        optional = self.optional? || other.optional?
        type = AST::Types::Proc.new(
          params: self.type.params + other.type.params,
          return_type: AST::Types::Union.build(types: [self.type.return_type, other.type.return_type])
        )
        self.class.new(
          type: type,
          optional: optional
        )
      end
    end
  end
end
