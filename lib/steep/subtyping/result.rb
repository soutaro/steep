module Steep
  module Subtyping
    module Result
      class Base
        attr_reader :relation

        def initialize(relation)
          @relation = relation
        end

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

        def failure_path(path = [])
          raise
        end
      end

      class Skip < Base
        def success?
          raise "The test is skipped: #{relation}"
        end

        def failure_path(path = [])
          raise
        end
      end

      class Expand < Base
        attr_reader :child

        def initialize(relation, &block)
          super relation
          @child = yield relation

          raise if @child == true
        end

        def success?
          child.success?
        end

        def failure_path(path = [])
          if child.failure?
            path.unshift(self)
            child.failure_path(path)
          end
        end
      end

      class All < Base
        attr_reader :branches

        def initialize(relation)
          super relation
          @branches = []
          @failure = false
        end

        # Returns `false` if no future `#add` changes the result.
        def add(*relations, &block)
          relations.each do |relation|
            if success?
              result = yield(relation)
              branches << result
            else
              # Already failed.
              branches << Skip.new(relation)
            end
          end

          # No need to test more branches if already failed.
          success?
        end

        def success?
          !failure?
        end

        def failure?
          @failure ||= branches.any?(&:failure?)
        end

        def failure_path(path = [])
          if failure?
            r = branches.find(&:failure?)
            path.unshift(self)
            r.failure_path(path)
          end
        end
      end

      class Any < Base
        attr_reader :branches

        def initialize(relation)
          super relation
          @branches = []
          @success = false
        end

        # Returns `false` if no future `#add` changes the result.
        def add(*relations, &block)
          relations.each do |relation|
            if failure?
              result = yield(relation)
              branches << result
            else
              # Already succeeded.
              branches << Skip.new(relation)
            end
          end

          # No need to test more branches if already succeeded.
          failure?
        end

        def success?
          @success ||= branches.any?(&:success?)
        end

        def failure_path(path = [])
          if failure?
            path.unshift(self)
            if r = branches.find(&:failure?)
              r.failure_path(path)
            else
              path
            end
          end
        end
      end

      class Success < Base
        def success?
          true
        end

        def failure_path(path = [])
          nil
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

        attr_reader :error

        def initialize(relation, error)
          super relation
          @error = error
        end

        def success?
          false
        end

        def failure_path(path = [])
          path.unshift(self)
          path
        end
      end

      module Helper
        def Skip(relation)
          Skip.new(relation)
        end

        def Expand(relation, &block)
          Expand.new(relation, &block)
        end

        def All(relation, &block)
          All.new(relation).tap(&block)
        end

        def Any(relation, &block)
          Any.new(relation).tap(&block)
        end

        def Success(relation)
          Success.new(relation)
        end

        alias success Success

        def Failure(relation, error = nil)
          Failure.new(relation, error || yield)
        end
      end
    end
  end
end
