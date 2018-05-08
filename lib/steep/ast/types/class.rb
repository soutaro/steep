module Steep
  module AST
    module Types
      class Class
        attr_reader :location

        def initialize(location: nil)
          @location = location
        end

        def ==(other)
          other.is_a?(Class)
        end

        def hash
          self.class.hash
        end

        alias eql? ==

        def subst(s)
          s.module_type or raise "Unexpected substitution: #{inspect}"
        end

        def free_variables
          Set.new
        end

        def level
          [0]
        end
      end
    end
  end
end
