module Steep
  module AST
    module Types
      class Top
        attr_reader :location

        def initialize(location: nil)
          @location = location
        end

        def ==(other, ignore_location: false)
          other.is_a?(Top) && (ignore_location || !other.location || !location || other.location == location)
        end

        def hash
          self.class.hash
        end

        def eql?(other)
          __send__(:==, other, ignore_location: true)
        end

        def subst(s)
          self
        end

        def to_s
          "⟙"
        end

        def free_variables
          Set.new
        end
      end
    end
  end
end
