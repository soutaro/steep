module Steep
  module AST
    module Types
      class Void
        extend SharedInstance
        
        def ==(other)
          other.is_a?(Void)
        end

        def hash
          self.class.hash
        end

        alias eql? ==

        def subst(s)
          self
        end

        def to_s
          "void"
        end

        include Helper::NoFreeVariables

        include Helper::NoChild

        def level
          [0]
        end
      end
    end
  end
end
