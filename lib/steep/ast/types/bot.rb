module Steep
  module AST
    module Types
      class Bot
        attr_reader :location

        def initialize(location: nil)
          @location = location
        end

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
          "⟘"
        end

        def free_variables
          Set.new
        end

        def level
          [2]
        end
      end
    end
  end
end
