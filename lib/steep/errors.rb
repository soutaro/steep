module Steep
  module Errors
    class Base
      attr_reader :node

      def initialize(node:)
        @node = node
      end

      def location_to_str
        "#{node.loc.expression.source_buffer.name}:#{node.loc.first_line}:#{node.loc.column}"
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

      def to_s
        "#{location_to_str}: IncompatibleAssignment: lhs_type=#{lhs_type}, rhs_type=#{rhs_type}"
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

      def to_s
        "#{location_to_str}: ArgumentTypeMismatch: type=#{type}, method=#{method}"
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

      def to_s
        "#{location_to_str}: NoMethodError: type=#{type}, method=#{method}"
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

      def to_s
        "#{location_to_str}: ReturnTypeMismatch: expected=#{expected}, actual=#{actual}"
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

    class MethodParameterTypeMismatch < Base
      def to_s
        "#{location_to_str}: MethodParameterTypeMismatch: method=#{node.children[0]}"
      end
    end

    class MethodBodyTypeMismatch < Base
      attr_reader :expected
      attr_reader :actual

      def initialize(node:, expected:, actual:)
        super(node: node)
        @expected = expected
        @actual = actual
      end

      def to_s
        method = case node.type
                 when :def
                   node.children[0]
                 when :defs
                   prefix = node.children[0].type == :self ? "self" : "*"
                   "#{prefix}.#{node.children[1]}"
                 end
        "#{location_to_str}: MethodBodyTypeMismatch: method=#{method}, expected=#{expected}, actual=#{actual}"
      end
    end

    class UnexpectedYield < Base
      def to_s
        "#{location_to_str}: UnexpectedYield"
      end
    end

    class UnexpectedSuper < Base
      attr_reader :method

      def initialize(node:, method:)
        super(node: node)
        @method = method
      end

      def to_s
        "#{location_to_str}: UnexpectedSuper: method=#{method}"
      end
    end

    class MethodDefinitionMissing < Base
      attr_reader :module_name
      attr_reader :kind
      attr_reader :missing_method

      def initialize(node:, module_name:, kind:, missing_method:)
        super(node: node)
        @module_name = module_name
        @kind = kind
        @missing_method = missing_method
      end

      def to_s
        method = case kind
                 when :instance
                   "#{missing_method}"
                 when :module
                   "self.#{missing_method}"
                 end
        "#{location_to_str}: MethodDefinitionMissing: module=#{module_name}, method=#{method}"
      end
    end
  end
end
