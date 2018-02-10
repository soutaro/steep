module Steep
  module AST
    module Types
      class Class
        attr_reader :location

        def initialize(location: nil)
          @location = location
        end

        def ==(other)
          other.is_a?(Class) && (!other.location || !location || other.location == location)
        end

        def subst(s)
          s.module_type or raise "Unexpected substitution: #{inspect}"
        end

        def free_variables
          Set.new
        end
      end
    end
  end
end
