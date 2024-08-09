module Steep
  module AST
    module Types
      class Nil
        extend SharedInstance
        
        def ==(other)
          other.is_a?(Nil)
        end

        def hash
          self.class.hash
        end

        alias eql? ==

        def subst(s)
          self
        end

        def to_s
          "nil"
        end

        include Helper::NoFreeVariables

        include Helper::NoChild

        def level
          [0]
        end

        def back_type
          Name::Instance.new(name: Builtin::NilClass.module_name,
                             args: [])
        end
      end
    end
  end
end

