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
        end

        class BlockMismatchError
          attr_reader :name

          def initialize(name:)
            @name = name
          end
        end

        class ParameterMismatchError
          attr_reader :name

          def initialize(name:)
            @name = name
          end
        end

        class PolyMethodError
          attr_reader :name

          def initialize(name:)
            @name = name
          end
        end

        class UnknownPairError
          attr_reader :constraint

          def initialize(constraint:)
            @constraint = constraint
          end
        end

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
