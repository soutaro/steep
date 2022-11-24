module Steep
  module AST
    module Types
      class Record
        attr_reader :location
        attr_reader :elements

        def initialize(elements:, location: nil)
          @elements = elements
          @location = location
        end

        def ==(other)
          other.is_a?(Record) && other.elements == elements
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
          strings = elements.keys.sort.map do |key|
            "#{key.inspect} => #{elements[key]}"
          end
          "{ #{strings.join(", ")} }"
        end

        def free_variables()
          @fvs ||= Set.new.tap do |set|
            elements.each_value do |type|
              set.merge(type.free_variables)
            end
          end
        end

        include Helper::ChildrenLevel

        def each_child(&block)
          if block
            elements.each_value(&block)
          else
            elements.each_value
          end
        end

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
