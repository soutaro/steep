module Steep
  module AST
    module Types
      class Literal
        attr_reader :value

        def initialize(value:)
          @value = value
        end

        # Returns a shared instance for the given value
        #
        # String values are frozen to make the sharing safe.
        # Note that the sharing is best-effort -- types constructed with `.new` are still
        # equal to the shared instances by the structural comparison.
        #
        def self.intern(value:)
          table = (@table ||= {}) #: Hash[value, Literal]
          if type = table[value]
            type
          else
            if value.is_a?(String) && !value.frozen?
              value = value.dup.freeze
            end
            table[value] = new(value: value)
          end
        end

        def ==(other)
          other.is_a?(Literal) &&
            other.value == value
        end

        def hash
          self.class.hash ^ value.hash
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

          Name::Instance.intern(name: klass.module_name, args: [])
        end
      end
    end
  end
end
