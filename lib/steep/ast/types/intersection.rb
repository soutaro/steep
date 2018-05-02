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

        def self.build(types:, location: nil)
          types.flat_map do |type|
            if type.is_a?(Intersection)
              type.types
            else
              [type]
            end
          end.map do |type|
            case type
            when AST::Types::Any
              return AST::Types::Any.new()
            when AST::Types::Bot
              return AST::Types::Bot.new()
            when AST::Types::Top
              nil
            else
              type
            end
          end.compact.uniq.yield_self do |tys|
            if tys.size == 1
              tys.first
            else
              new(types: tys.sort_by(&:hash), location: location)
            end
          end
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

        def free_variables
          types.each.with_object(Set.new) do |type, set|
            set.merge(type.free_variables)
          end
        end

        include Helper::ChildrenLevel

        def level
          [0] + level_of_children(types)
        end
      end
    end
  end
end
