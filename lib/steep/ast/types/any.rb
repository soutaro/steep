module Steep
  module AST
    module Types
      class Any
        extend SharedInstance

        def ==(other)
          other.is_a?(Any)
        end

        def hash
          self.class.hash
        end

        alias eql? ==

        def subst(s)
          self
        end

        def to_s
          "untyped"
        end

        include Helper::NoFreeVariables

        include Helper::NoChild

        def level
          [1]
        end
      end
    end
  end
end
