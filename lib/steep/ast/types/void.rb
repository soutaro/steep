module Steep
  module AST
    module Types
      class Void
        attr_reader :location

        def initialize(location: nil)
          @location = location
        end

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
          "any"
        end

        def free_variables
          Set.new
        end
      end
    end
  end
end
