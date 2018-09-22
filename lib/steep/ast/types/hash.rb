module Steep
  module AST
    module Types
      class Hash
        attr_reader :location
        attr_reader :elements

        def initialize(elements:, location: nil)
          @elements = elements
          @location = location
        end

        def ==(other)
          other.is_a?(Hash) && other.elements == elements
        end

        def hash
          self.class.hash ^ elements.hash
        end

        alias eql? ==

        def subst(s)
          self.class.new(location: location,
                         elements: elements.transform_values {|type| type.subst(s) })
        end

        def to_s
          "{ #{elements.map {|key, value| "#{key.inspect} => #{value}" }.join(", ")} }"
        end

        def free_variables
          elements.each_value.with_object(Set.new) do |type, set|
            set.merge(type.free_variables)
          end
        end

        include Helper::ChildrenLevel

        def level
          [0] + level_of_children(elements.values)
        end

        def with_location(new_location)
          self.class.new(elements: elements, location: new_location)
        end
      end
    end
  end
end
