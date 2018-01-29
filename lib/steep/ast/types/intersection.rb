module Steep
  module AST
    module Types
      class Intersection
        attr_reader :types
        attr_reader :location

        def initialize(types:, location: nil)
          @types = types
          @location = location
        end

        def ==(other, ignore_location: false)
          other.is_a?(Intersection) &&
            other.types == types &&
            (ignore_location || !other.location || !location || other.location == location)
        end

        def hash
          self.class.hash ^ types.hash
        end

        def eql?(other)
          __send__(:==, other, ignore_location: true)
        end

        def subst(s)
          self.class.new(location: location,
                         types: types.map {|ty| ty.subst(s) })
        end

        def to_s
          "(#{types.join(" & ")})"
        end
      end
    end
  end
end
