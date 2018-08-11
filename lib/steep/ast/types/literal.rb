module Steep
  module AST
    module Types
      class Literal
        attr_reader :location
        attr_reader :value

        def initialize(value:, location: nil)
          @location = location
          @value = value
        end

        def ==(other)
          other.is_a?(Literal) &&
            other.value == value
        end

        def hash
          self.class.hash
        end

        alias eql? ==

        def subst(s)
          self
        end

        def to_s
          value.inspect
        end

        def free_variables
          Set.new
        end

        def level
          [0]
        end

        def with_location(new_location)
          self.class.new(location: new_location)
        end

        def back_type
          case value
          when Integer
            Name.new_instance(name: Builtin::Integer.module_name, location: location)
          when String
            Name.new_instance(name: Builtin::String.module_name, location: location)
          when Symbol
            Name.new_instance(name: Builtin::Symbol.module_name, location: location)
          else
            raise "Unexpected literal type: #{value.inspect}"
          end
        end
      end
    end
  end
end
