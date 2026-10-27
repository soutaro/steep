module Steep
  module AST
    module Types
      # The negation type `!T`: the values that are not of type `T`.
      #
      # This is an internal type of the set-theoretic type checking. RBS has no syntax for it yet, so it
      # cannot be written in signatures or annotations, but it is printed as `!T` in hovers and diagnostics.
      class Negation
        attr_reader :type

        def initialize(type:)
          @type = type
        end

        # Builds the negation of `type`, cancelling the trivial cases: `!!T` is `T`, `!top` is `bot`, and `!bot` is `top`.
        def self.build(type:)
          case type
          when Negation
            type.type
          when Top
            Bot.instance
          when Bot
            Top.instance
          else
            new(type: type)
          end
        end

        def ==(other)
          other.is_a?(Negation) && other.type == type
        end

        def hash
          @hash ||= self.class.hash ^ type.hash
        end

        alias eql? ==

        def subst(s)
          ty = type.subst(s)
          if ty.equal?(type)
            self
          else
            Negation.build(type: ty)
          end
        end

        def to_s
          case type
          when Proc
            "!(#{type})"
          else
            # Union and intersection types print their own parentheses.
            "!#{type}"
          end
        end

        def free_variables
          type.free_variables
        end

        def each_child(&block)
          if block
            yield type
          else
            enum_for :each_child
          end
        end

        def map_type(&block)
          Negation.build(type: yield(type))
        end

        include Helper::ChildrenLevel

        def level
          [0] + level_of_children([type])
        end
      end
    end
  end
end
