module Steep
  module AST
    module Types
      class Any
        attr_reader :location

        def initialize(location: nil)
          @location = location
        end

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
          "any"
        end

        def free_variables
          Set.new
        end

        def level
          [1]
        end

        def with_location(new_location)
          self.class.new(location: new_location)
        end
      end
    end
  end
end
