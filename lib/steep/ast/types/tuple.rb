module Steep
  module AST
    module Types
      class Tuple
        attr_reader :types

        def initialize(types:)
          @types = types
        end

        def ==(other)
          other.is_a?(Tuple) &&
            other.types == types
        end

        def hash
          self.class.hash ^ types.hash
        end

        alias eql? ==

        def subst(s)
          self.class.new(types: types.map {|ty| ty.subst(s) })
        end

        def to_s
          "[#{types.join(", ")}]"
        end

        def free_variables()
          @fvs ||= each_child.with_object(Set[]) do |type, set| #$ Set[variable]
            set.merge(type.free_variables)
          end
        end

        include Helper::ChildrenLevel

        def each_child(&block)
          if block
            types.each(&block)
          else
            types.each
          end
        end

        def map_type(&block)
          Tuple.new(types: types.map(&block))
        end

        def level
          [0] + level_of_children(types)
        end

        def with_location(new_location)
          self.class.new(types: types)
        end
      end
    end
  end
end
