module Steep
  module Interface
    class MethodType
      attr_reader :type_params
      attr_reader :type
      attr_reader :block
      attr_reader :method_decls

      def initialize(type_params:, type:, block:, method_decls:)
        @type_params = type_params
        @type = type
        @block = block
        @method_decls = method_decls
      end

      def ==(other)
        other.is_a?(self.class) &&
          other.type_params == type_params &&
          other.type == type &&
          other.block == block
      end

      alias eql? ==

      def hash
        type_params.hash ^ type.hash ^ block.hash
      end

      def free_variables
        @fvs ||= Set.new.tap do |set|
          set.merge(type.free_variables)
          if block
            set.merge(block.free_variables)
          end
          set.subtract(type_params.map(&:name))
        end
      end

      def subst(s)
        return self if s.empty?
        return self if each_type.none? {|t| s.apply?(t) }

        if type_params.any? {|param| s.key?(param.name) }
          s_ = s.except(type_params.map(&:name))
        else
          s_ = s
        end

        ty = type.subst(s_)
        bl = block&.subst(s_)

        if ty == type && bl == block
          self
        else
          self.class.new(type_params: type_params, type: ty, block: bl, method_decls: method_decls)
        end
      end

      def each_type(&block)
        if block_given?
          type.each_type(&block)
          self.block&.tap do
            self.block.type.params.each_type(&block)
            yield(self.block.type.return_type)
          end
        else
          enum_for :each_type
        end
      end

      def instantiate(s)
        self.class.new(type_params: [],
                       type: type.subst(s),
                       block: block&.subst(s),
                       method_decls: method_decls)
      end

      def with(type_params: self.type_params, type: self.type, block: self.block, method_decls: self.method_decls)
        self.class.new(type_params: type_params,
                       type: type,
                       block: block,
                       method_decls: method_decls)
      end

      def to_s
        type_params = !self.type_params.empty? ? "[#{self.type_params.join(", ")}] " : ""
        params = type.params.to_s
        return_type = type.return_type
        block = self.block ? " #{self.block}" : ""

        "#{type_params}#{params}#{block} -> #{return_type}"
      end

      def map_type(&block)
        self.class.new(type_params: type_params,
                       type: type.map_type(&block),
                       block: self.block&.yield_self {|blk| blk.map_type(&block) },
                       method_decls: method_decls)
      end

      # Returns a new method type which can be used for the method implementation type of both `self` and `other`.
      #
      def unify_overload(other)
        type_params_1, s1 = TypeParam.rename(self.type_params)
        type_params_2, s2 = TypeParam.rename(other.type_params)
        type_params = type_params_1 + type_params_2

        block = case
                when self.block && other.block
                  self.block.subst(s1) + other.block.subst(s2)
                when self.block
                  self.block.to_optional.subst(s1)
                when other.block
                  other.block.to_optional.subst(s2)
                end

        self.class.new(
          type_params: type_params,
          type: Function.new(
            params: type.params.subst(s1) + other.type.params.subst(s2),
            return_type: AST::Types::Union.build(
              types: [type.return_type.subst(s1), other.type.return_type.subst(s2)]
            ),
            location: nil
          ),
          block: block,
          method_decls: method_decls + other.method_decls
        )
      end

      def +(other)
        unify_overload(other)
      end

      # Returns a method type which is a super-type of both self and other.
      #   self <: (self | other) && other <: (self | other)
      #
      # Returns nil if self and other are incompatible.
      #
      def |(other)
        if other.type_params.empty?
          type_params = self.type_params
        else
          other_params, s2 = TypeParam.rename(other.type_params)
          other = other.instantiate(s2)
          type_params = self.type_params + other_params
        end

        params = self.type.params & other.type.params or return
        block = case
                when self.block && other.block
                  block_params = self.block.type.params | other.block.type.params
                  block_return_type = AST::Types::Intersection.build(types: [self.block.type.return_type, other.block.type.return_type])
                  block_type = Function.new(params: block_params, return_type: block_return_type, location: nil)
                  Block.new(
                    type: block_type,
                    optional: self.block.optional && other.block.optional
                  )
                when self.block && self.block.optional?
                  self.block
                when other.block && other.block.optional?
                  other.block
                when !self.block && !other.block
                  nil
                else
                  return
                end
        return_type = AST::Types::Union.build(types: [self.type.return_type, other.type.return_type])

        MethodType.new(
          type_params: type_params,
          type: Function.new(params: params, return_type: return_type, location: nil),
          block: block,
          method_decls: method_decls + other.method_decls
        )
      end

      # Returns a method type which is a sub-type of both self and other.
      #   (self & other) <: self && (self & other) <: other
      #
      # Returns nil if self and other are incompatible.
      #
      def &(other)
        if other.type_params.empty?
          type_params = self.type_params
        else
          other_params, s2 = TypeParam.rename(other.type_params)
          other = other.instantiate(s2)
          type_params = self.type_params + other_params
        end

        params = self.type.params | other.type.params
        block = case
                when self.block && other.block
                  block_params = self.block.type.params & other.block.type.params or return
                  block_return_type = AST::Types::Union.build(types: [self.block.type.return_type, other.block.type.return_type])
                  block_type = Function.new(params: block_params, return_type: block_return_type, location: nil)
                  Block.new(
                    type: block_type,
                    optional: self.block.optional || other.block.optional
                  )

                else
                  self.block || other.block
                end

        return_type = AST::Types::Intersection.build(types: [self.type.return_type, other.type.return_type])

        MethodType.new(
          type_params: type_params,
          type: Function.new(params: params, return_type: return_type, location: nil),
          block: block,
          method_decls: method_decls + other.method_decls
        )
      end
    end
  end
end
