module Steep
  module AST
    module Types
      class Record
        attr_reader :elements, :required_keys

        def initialize(elements:, required_keys:)
          @elements = elements
          @required_keys = required_keys
        end

        def ==(other)
          other.is_a?(Record) && other.elements == elements && other.required_keys == required_keys
        end

        def hash
          self.class.hash ^ elements.hash ^ required_keys.hash
        end

        alias eql? ==

        def subst(s)
          self.class.new(
            elements: elements.transform_values {|type| type.subst(s) },
            required_keys: required_keys
          )
        end

        def to_s
          strings = elements.keys.sort_by(&:to_s).map do |key|
            if optional?(key)
              "?#{key.inspect} => #{elements[key]}"
            else
              "#{key.inspect} => #{elements[key]}"
            end
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

        def map_type(&block)
          self.class.new(
            elements: elements.transform_values(&block),
            required_keys: required_keys
          )
        end

        def level
          [0] + level_of_children(elements.values)
        end

        def required?(key)
          required_keys.include?(key)
        end

        def optional?(key)
          !required_keys.include?(key)
        end
      end
    end
  end
end
