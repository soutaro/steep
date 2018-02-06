module Steep
  module AST
    module Types
      class Self
        attr_reader :location

        def initialize(location: nil)
          @location = location
        end

        def ==(other, ignore_location: false)
          other.is_a?(Self) &&
            (ignore_location || !other.location || !location || other.location == location)
        end

        def to_s
          "self"
        end

        def subst(s)
          s.self_type or raise "Unexpected substitution: #{inspect}"
        end
      end
    end
  end
end
