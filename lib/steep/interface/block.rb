module Steep
  module Interface
    class Block
      attr_reader :type
      attr_reader :optional
      attr_reader :self_type

      def initialize(type:, optional:, self_type:)
        @type = type
        @optional = optional
        @self_type = self_type
      end

      def optional?
        @optional
      end

      def required?
        !optional?
      end

      def to_optional
        self.class.new(
          type: type,
          self_type: self_type,
          optional: true
        )
      end

      def ==(other)
        other.is_a?(self.class) && other.type == type && other.optional == optional && other.self_type == self_type
      end

      alias eql? ==

      def hash
        type.hash ^ optional.hash ^ self_type.hash
      end

      def closed?
        type.closed?
      end

      def subst(s)
        ty = type.subst(s)
        st = self_type.subst(s) if self_type

        if ty == type && st == self_type
          self
        else
          self.class.new(type: ty, self_type: st, optional: optional)
        end
      end

      def free_variables()
        @fvs ||= type.free_variables + (self_type&.free_variables || Set[])
      end

      def to_s
        self_binding = self_type ? "[self: #{self_type}] " : ""
        "#{optional? ? "?" : ""}{ #{type.params} #{self_binding}-> #{type.return_type} }"
      end

      def map_type(&block)
        self.class.new(
          type: type.map_type(&block),
          self_type: self_type&.map_type(&block),
          optional: optional
        )
      end

      def to_proc_type
        proc = AST::Types::Proc.new(type: type, self_type: self_type, block: nil)

        if optional?
          AST::Types::Union.build(types: [proc, AST::Builtin.nil_type])
        else
          proc
        end
      end

      def +(other)
        optional = self.optional? || other.optional?
        type = Function.new(
          params: self.type.params + other.type.params,
          return_type: AST::Types::Union.build(types: [self.type.return_type, other.type.return_type]),
          location: nil
        )

        self_types = [self.self_type, other.self_type].compact

        self.class.new(
          type: type,
          optional: optional,
          self_type:
            unless self_types.empty?
              AST::Types::Union.build(types: self_types)
            end
        )
      end
    end
  end
end
