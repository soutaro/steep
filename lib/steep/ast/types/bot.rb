module Steep
  module AST
    module Types
      class Bot
        extend SharedInstance
        
        def ==(other)
          other.is_a?(Bot)
        end

        def hash
          self.class.hash
        end

        alias eql? ==

        def subst(s)
          self
        end

        def to_s
          "bot"
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
