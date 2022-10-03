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
        if block
          type.each_type(&block)
          if block()
            yield(block().self_type) if block().self_type
            block().type.params.each_type(&block)
            yield(block().type.return_type)
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

        block =
          case
          when (b = self.block) && (ob = other.block)
            b.subst(s1) + ob.subst(s2)
          when b = self.block
            b.to_optional.subst(s1)
          when ob = other.block
            ob.to_optional.subst(s2)
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

      def equals_modulo_type_params?(other)
        case
        when self.type_params.empty? && other.type_params.empty?
          self == other
        when self.type_params.size == other.type_params.size
          new_names = self.type_params.map(&:name)

          self_params, self_subst = TypeParam.rename(self.type_params, self.type_params.map(&:name), new_names)
          other_params, other_subst = TypeParam.rename(other.type_params, other.type_params.map(&:name), new_names)

          self_params == other_params && self.instantiate(self_subst) == other.instantiate(other_subst)
        else
          false
        end
      end

      def self.union(type1, type2, check)
        try_type_params(
          type1,
          type2,
          check,
          -> (t1, t2) { t1 | t2 },
          -> (original, generated) { Subtyping::Relation.new(sub_type: original, super_type: generated) }
        )
      end

      def self.intersection(type1, type2, check)
        try_type_params(
          type1,
          type2,
          check,
          -> (t1, t2) { t1 & t2 },
          -> (original, generated) { Subtyping::Relation.new(sub_type: generated, super_type: original) }
        )
      end

      def self.try_type_params(type1, type2, check, generate, relation)
        return type1 if type1.equals_modulo_type_params?(type2)

        case
        when type1.type_params.empty? && type2.type_params.empty?
          generate[type1, type2]
        when type1.type_params.empty?
          if mt = generate[type1, type2.with(type_params: [])]
            mt.with(type_params: type2.type_params)
          end
        when type2.type_params.empty?
          if mt = generate[type1.with(type_params: []), type2]
            mt.with(type_params: type1.type_params)
          end
        when type1.type_params.size == type2.type_params.size
          params1, s1 = TypeParam.rename(type1.type_params)
          params2, s2 = TypeParam.rename(type2.type_params)

          type1_ = type1.instantiate(s1)
          type2_ = type2.instantiate(s2)
          if mt = generate[type1_, type2_]
            check.push_variable_bounds(params1 + params2) do
            variables = type1.type_params.map(&:name) + type2.type_params.map(&:name)
            constraints = Subtyping::Constraints.new(unknowns: variables)

            check.with_context(self_type: AST::Builtin.any_type, instance_type: AST::Builtin.any_type, class_type: AST::Builtin.any_type, constraints: constraints) do
                result1 = check.check_method_type(:__method_on_type1, relation[type1.with(type_params: []), mt])
                result2 = check.check_method_type(:__method_on_type2, relation[type2.with(type_params: []), mt])

                if result1.success? && result2.success?
                  unless type1.type_params.map(&:name).zip(type2.type_params.map(&:name)).all? {|pair|
                    constraints.upper_bound(pair[0]) == constraints.upper_bound(pair[1] || raise) &&
                       constraints.lower_bound(pair[0]) == constraints.lower_bound(pair[1] || raise)
                  }
                    return
                  end

                  params2_, s2_ = TypeParam.rename(type2.type_params, type2.type_params.map(&:name), type1.type_params.map(&:name))
                  if mt_ = generate[type1.with(type_params: []), type2.instantiate(s2_)]
                    mt_.with(
                      type_params: type1.type_params.map.with_index {|param1, index|
                        param2 = params2_[index] or raise
                        ub1 = param1.upper_bound
                        ub2 = param2.upper_bound

                        case
                        when ub1 && ub2
                          param1.update(upper_bound: AST::Types::Union.build(types: [ub1, ub2]))
                        when ub2
                          param1.update(upper_bound: ub2)
                        else
                          param1
                        end
                      }
                    )
                  end
                end
              end
            end
          end
        end
      end

      def |(other)
        return self if other == self

        params = self.type.params & other.type.params or return
        block =
          case
          when (b = block()) && (ob = other.block)
            self_type =
              case
              when (self_self = b.self_type) && (other_self = ob.self_type)
                AST::Types::Union.build(types: [self_self, other_self])
              when b.self_type || ob.self_type
                AST::Types::Bot.new()
              else
                nil
              end

            # Return when the two block parameters are imcompatible.
            return unless b.type.params & ob.type.params

            block_params = b.type.params | ob.type.params or return

            block_return_type = AST::Types::Intersection.build(types: [b.type.return_type, ob.type.return_type])
            block_type = Function.new(params: block_params, return_type: block_return_type, location: nil)

            Block.new(
              type: block_type,
              optional: b.optional && ob.optional,
              self_type: self_type
            )
          when (b = block()) && b.optional?
            b
          when other.block && other.block.optional?
            other.block
          when !self.block && !other.block
            nil
          else
            return
          end
        return_type = AST::Types::Union.build(types: [self.type.return_type, other.type.return_type])

        MethodType.new(
          type_params: [],
          type: Function.new(params: params, return_type: return_type, location: nil),
          block: block,
          method_decls: method_decls + other.method_decls
        )
      end

      def &(other)
        return self if self == other

        params = self.type.params | other.type.params or return
        block =
          case
          when (b = self.block) && (ob = other.block)
            self_type =
              case
              when (self_self = b.self_type) && (other_self = ob.self_type)
                AST::Types::Intersection.build(types: [self_self, other_self])
              when b.self_type || ob.self_type
                AST::Types::Top.new()
              else
                nil
              end

            block_params = b.type.params & ob.type.params or return
            block_return_type = AST::Types::Union.build(types: [b.type.return_type, ob.type.return_type])
            block_type = Function.new(params: block_params, return_type: block_return_type, location: nil)
            Block.new(
              type: block_type,
              optional: b.optional || ob.optional,
              self_type: self_type
            )
          else
            self.block || other.block
          end

        return_type = AST::Types::Intersection.build(types: [self.type.return_type, other.type.return_type])

        MethodType.new(
          type_params: [],
          type: Function.new(params: params, return_type: return_type, location: nil),
          block: block,
          method_decls: method_decls + other.method_decls
        )
      end
    end
  end
end
