module Steep
  module Errors
    class Base
      attr_reader :node

      def initialize(node:)
        @node = node
      end
    end

    class IncompatibleAssignment < Base
      attr_reader :lhs_type
      attr_reader :rhs_type

      def initialize(node:, lhs_type:, rhs_type:)
        super(node: node)
        @lhs_type = lhs_type
        @rhs_type = rhs_type
      end
    end

    class ArgumentTypeMismatch < Base
      attr_reader :type
      attr_reader :method

      def initialize(node:, type:, method:)
        super(node: node)
        @type = type
        @method = method
      end
    end

    class NoMethod < Base
      attr_reader :type
      attr_reader :method

      def initialize(node:, type:, method:)
        super(node: node)
        @type = type
        @method = method
      end
    end

    class ReturnTypeMismatch < Base
      attr_reader :expected
      attr_reader :actual

      def initialize(node:, expected:, actual:)
        super(node: node)
        @expected = expected
        @actual = actual
      end
    end

    class UnexpectedBlockGiven < Base
      attr_reader :method
      attr_reader :type

      def initialize(node:, type:, method:)
        super(node: node)
        @type = type
        @method = method
      end
    end

    class BlockTypeMismatch < Base
      attr_reader :expected
      attr_reader :actual

      def initialize(node:, expected:, actual:)
        super(node: node)
        @expected = expected
        @actual = actual
      end
    end

    class BreakTypeMismatch < Base
      attr_reader :expected
      attr_reader :actual

      def initialize(node:, expected:, actual:)
        super(node: node)
        @expected = expected
        @actual = actual
      end
    end
  end
end
