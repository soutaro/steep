module Steep
  module AST
    module Types
      class Top
        attr_reader :location

        def initialize(location: nil)
          @location = location
        end

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

        def with_location(new_location)
          self.class.new(location: new_location)
        end
      end
    end
  end
end
