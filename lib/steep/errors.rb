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

    class InvalidArgument < Base
      attr_reader :expected
      attr_reader :actual

      def initialize(node:, expected:, actual:)
        super(node: node)
        @expected = expected
        @actual = actual
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

    class ExpectedArgumentMissing < Base
      attr_reader :index

      def initialize(node:, index:)
        super(node: node)
        @index = index
      end
    end

    class ExtraArgumentGiven < Base
      attr_reader :index

      def initialize(node:, index:)
        super(node: node)
        @index = index
      end
    end

    class ExpectedKeywordMissing < Base
      attr_reader :keyword

      def initialize(node:, keyword:)
        super(node: node)
        @keyword = keyword
      end
    end

    class ExtraKeywordGiven < Base
      attr_reader :keyword

      def initialize(node:, keyword:)
        super(node: node)
        @keyword = keyword
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
  end
end
