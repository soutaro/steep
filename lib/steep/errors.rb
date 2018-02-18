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

      def print_to(io)
        io.puts to_s
      end
    end

    module ResultPrinter
      def print_result_to(io, level: 2)
        indent = " " * level
        result.trace.each do |s, t|
          case s
          when Interface::Method
            io.puts "#{indent}#{s.name}(#{s.type_name}) <: #{t.name}(#{t.type_name})"
          when Interface::MethodType
            io.puts "#{indent}#{s.location.source} <: #{t.location.source} (#{s.location.name}:#{s.location.start_line})"
          else
            io.puts "#{indent}#{s} <: #{t}"
          end
        end
        io.puts "#{indent}  #{result.error.message}"
      end

      def print_to(io)
        io.puts to_s
        print_result_to io
      end
    end

    class IncompatibleAssignment < Base
      attr_reader :lhs_type
      attr_reader :rhs_type
      attr_reader :result

      include ResultPrinter

      def initialize(node:, lhs_type:, rhs_type:, result:)
        super(node: node)
        @lhs_type = lhs_type
        @rhs_type = rhs_type
        @result = result
      end

      def to_s
        "#{location_to_str}: IncompatibleAssignment: lhs_type=#{lhs_type}, rhs_type=#{rhs_type}"
      end
    end

    class IncompatibleArguments < Base
      attr_reader :node
      attr_reader :method_type

      def initialize(node:, method_type:)
        super(node: node)
        @method_type = method_type
      end

      def to_s
        "#{location_to_str}: IncompatibleArguments: method_type=#{method_type}"
      end
    end

    class ArgumentTypeMismatch < Base
      attr_reader :node
      attr_reader :expected
      attr_reader :actual

      def initialize(node:, expected:, actual:)
        super(node: node)
        @expected = expected
        @actual = actual
      end

      def to_s
        "#{location_to_str}: ArgumentTypeMismatch: expected=#{expected}, actual=#{actual}"
      end
    end

    class IncompatibleBlockParameters < Base
      attr_reader :node
      attr_reader :method_type

      def initialize(node:, method_type:)
        super(node: node)
        @method_type = method_type
      end

      def to_s
        "#{location_to_str}: IncompatibleBlockParameters: method_type=#{method_type}"
      end
    end

    class BlockParameterTypeMismatch < Base
      attr_reader :expected
      attr_reader :actual

      def initialize(node:, expected:, actual:)
        super(node: node)
        @expected = expected
        @actual = actual
      end

      def to_s
        "#{location_to_str}: BlockParameterTypeMismatch: expected=#{expected}, actual=#{actual}"
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
      attr_reader :result

      include ResultPrinter

      def initialize(node:, expected:, actual:, result:)
        super(node: node)
        @expected = expected
        @actual = actual
        @result = result
      end

      def to_s
        "#{location_to_str}: ReturnTypeMismatch: expected=#{expected}, actual=#{actual}"
      end
    end

    class UnexpectedBlockGiven < Base
      attr_reader :method_type

      def initialize(node:, method_type:)
        super(node: node)
        @method_type = method_type
      end

      def to_s
        "#{location_to_str}: UnexpectedBlockGiven: method_type=#{method_type.location&.source}"
      end
    end

    class RequiredBlockMissing < Base
      attr_reader :method_type

      def initialize(node:, method_type:)
        super(node: node)
        @method_type = method_type
      end

      def to_s
        "#{location_to_str}: RequiredBlockMissing: method_type=#{method_type.location&.source}"
      end
    end

    class BlockTypeMismatch < Base
      attr_reader :expected
      attr_reader :actual
      attr_reader :result

      include ResultPrinter

      def initialize(node:, expected:, actual:, result:)
        super(node: node)
        @expected = expected
        @actual = actual
        @result = result
      end

      def to_s
        "#{location_to_str}: BlockTypeMismatch: expected=#{expected}, actual=#{actual}"
      end
    end

    class BreakTypeMismatch < Base
      attr_reader :expected
      attr_reader :actual
      attr_reader :result

      include ResultPrinter

      def initialize(node:, expected:, actual:, result:)
        super(node: node)
        @expected = expected
        @actual = actual
        @result = result
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
      attr_reader :result

      include ResultPrinter

      def initialize(node:, expected:, actual:, result:)
        super(node: node)
        @expected = expected
        @actual = actual
        @result = result
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

    class UnexpectedDynamicMethod < Base
      attr_reader :module_name
      attr_reader :method_name

      def initialize(node:, module_name:, method_name:)
        @node = node
        @module_name = module_name
        @method_name = method_name
      end

      def to_s
        "#{location_to_str}: UnexpectedDynamicMethod: module=#{module_name}, method=#{method_name}"
      end
    end

    class FallbackAny < Base
      def initialize(node:)
        @node = node
      end

      def to_s
        "#{location_to_str}: FallbackAny"
      end
    end
  end
end
