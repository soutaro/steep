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

        include Helper::NoFreeVariables

        include Helper::NoChild

        def level
          [0]
        end

        def with_location(new_location)
          _ = self.class.new(value: value, location: new_location)
        end

        def back_type
          klass = case value
                  when Integer
                    Builtin::Integer
                  when String
                    Builtin::String
                  when Symbol
                    Builtin::Symbol
                  when true
                    Builtin::TrueClass
                  when false
                    Builtin::FalseClass
                  else
                    raise "Unexpected literal type: #{(_ = value).inspect}"
                  end

          Name::Instance.new(name: klass.module_name, args: [], location: location)
        end
      end
    end
  end
end
