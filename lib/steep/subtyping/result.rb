module Steep
  module Subtyping
    module Result
      class Base
        def failure?
          !success?
        end

        def then
          if success?
            yield self
          else
            self
          end
        end

        def else
          if failure?
            yield self
          else
            self
          end
        end
      end

      class Success < Base
        attr_reader :constraints

        def initialize(constraints:)
          @constraints = constraints
        end

        def success?
          true
        end
      end

      class Failure < Base
        class MethodMissingError
          attr_reader :name

          def initialize(name:)
            @name = name
          end

          def message
            "Method #{name} is missing"
          end
        end

        class BlockMismatchError
          attr_reader :name

          def initialize(name:)
            @name = name
          end

          def message
            "Method #{name} is incompatible for block"
          end
        end

        class ParameterMismatchError
          attr_reader :name

          def initialize(name:)
            @name = name
          end

          def message
            "Method #{name} or its block has incompatible parameters"
          end
        end

        class UnknownPairError
          attr_reader :relation

          def initialize(relation:)
            @relation = relation
          end

          def message
            "#{relation} does not hold"
          end
        end

        class PolyMethodSubtyping
          attr_reader :name

          def initialize(name:)
            @name = name
          end

          def message
            "Method #{name} requires uncheckable polymorphic subtyping"
          end
        end

        attr_reader :relation
        attr_reader :error
        attr_reader :trace

        def initialize(error:, trace:)
          @error = error
          @trace = trace.dup
        end

        def success?
          false
        end

        def merge_trace(trace)
          if trace.empty?
            self
          else
            self.class.new(error: error,
                           trace: trace + self.trace)
          end
        end

        def drop(n)
          self.class.new(error: error, trace: trace.drop(n))
        end
      end
    end
  end
end
