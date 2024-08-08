module Steep
  module AST
    module Types
      class Top
        extend SharedInstance

        def ==(other)
          other.is_a?(Top)
        end

        def hash
          self.class.hash
        end

        alias eql? ==

        def subst(s)
          self
        end

        def to_s
          "top"
        end

        include Helper::NoFreeVariables

        include Helper::NoChild

        def level
          [2]
        end
      end
    end
  end
end
