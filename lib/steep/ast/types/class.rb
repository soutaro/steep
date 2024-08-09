module Steep
  module AST
    module Types
      class Class
        extend SharedInstance

        def to_s
          "class"
        end

        def ==(other)
          other.is_a?(Class)
        end

        def hash
          self.class.hash
        end

        alias eql? ==

        def subst(s)
          if s.module_type
            s.module_type
          else
            self
          end
        end

        @@fvs = Set[instance]

        def free_variables
          @@fvs
        end

        include Helper::NoChild

        def level
          [0]
        end
      end
    end
  end
end
