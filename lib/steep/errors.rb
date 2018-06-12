module Steep
  module Errors
    class Base
      attr_reader :node

      def initialize(node:)
        @node = node
      end

      def location_to_str
        Rainbow("#{node.loc.expression.source_buffer.name}:#{node.loc.first_line}:#{node.loc.column}").red
      end

      def print_to(io)
        source = node.loc.expression.source
        io.puts "#{to_s} (#{Rainbow(source.split(/\n/).first).blue})"
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
            io.puts "#{indent}#{s} <: #{t} (#{s.location.name}:#{s.location.start_line})"
          else
            io.puts "#{indent}#{s} <: #{t}"
          end
        end
        io.puts "#{indent}  #{result.error.message}"
      end

      def print_to(io)
        super
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
      attr_reader :receiver_type
      attr_reader :method_type

      def initialize(node:, receiver_type:, method_type:)
        super(node: node)
        @receiver_type = receiver_type
        @method_type = method_type
      end

      def to_s
        "#{location_to_str}: IncompatibleArguments: receiver=#{receiver_type}, method_type=#{method_type}"
      end
    end

    class ArgumentTypeMismatch < Base
      attr_reader :node
      attr_reader :expected
      attr_reader :actual
      attr_reader :receiver_type

      def initialize(node:, receiver_type:, expected:, actual:)
        super(node: node)
        @receiver_type = receiver_type
        @expected = expected
        @actual = actual
      end

      def to_s
        "#{location_to_str}: ArgumentTypeMismatch: receiver=#{receiver_type}, expected=#{expected}, actual=#{actual}"
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

      def to_s
        "#{location_to_str}: BreakTypeMismatch: expected=#{expected}, actual=#{actual}"
      end
    end

    class UnexpectedJump < Base
      def to_s
        "#{location_to_str}: UnexpectedJump"
      end
    end

    class UnexpectedJumpValue < Base
      def to_s
        "#{location_to_str}: UnexpectedJumpValue"
      end
    end

    class MethodArityMismatch < Base
      def to_s
        "#{location_to_str}: MethodArityMismatch: method=#{node.children[0]}"
      end
    end

    class IncompatibleMethodTypeAnnotation < Base
      attr_reader :interface_method
      attr_reader :annotation_method
      attr_reader :result

      include ResultPrinter

      def initialize(node:, interface_method:, annotation_method:, result:)
        super(node: node)
        @interface_method = interface_method
        @annotation_method = annotation_method
        @result = result
      end

      def to_s
        "#{location_to_str}: IncompatibleMethodTypeAnnotation: interface_method=#{interface_method.type_name}.#{interface_method.name}, annotation_method=#{annotation_method.name}"
      end
    end

    class MethodDefinitionWithOverloading < Base
      attr_reader :method

      def initialize(node:, method:)
        super(node: node)
        @method = method
      end

      def to_s
        "#{location_to_str}: MethodDefinitionWithOverloading: method=#{method.name}, types=#{method.types.join(" | ")}"
      end
    end

    class MethodReturnTypeAnnotationMismatch < Base
      attr_reader :method_type
      attr_reader :annotation_type
      attr_reader :result

      include ResultPrinter

      def initialize(node:, method_type:, annotation_type:, result:)
        super(node: node)
        @method_type = method_type
        @annotation_type = annotation_type
        @result = result
      end

      def to_s
        "#{location_to_str}: MethodReturnTypeAnnotationMismatch: method_type=#{method_type.return_type}, annotation_type=#{annotation_type}"
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

    class UnknownConstantAssigned < Base
      attr_reader :type

      def initialize(node:, type:)
        super(node: node)
        @type = type
      end

      def to_s
        "#{location_to_str}: UnknownConstantAssigned: type=#{type}"
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

    class UnsatisfiableConstraint < Base
      attr_reader :method_type
      attr_reader :var
      attr_reader :sub_type
      attr_reader :super_type
      attr_reader :result

      def initialize(node:, method_type:, var:, sub_type:, super_type:, result:)
        super(node: node)
        @method_type = method_type
        @var = var
        @sub_type = sub_type
        @super_type = super_type
        @result = result
      end

      include ResultPrinter

      def to_s
        "#{location_to_str}: UnsatisfiableConstraint: method_type=#{method_type}, constraint=#{sub_type} <: '#{var} <: #{super_type}"
      end
    end

    class IncompatibleAnnotation < Base
      attr_reader :var_name
      attr_reader :result
      attr_reader :relation

      def initialize(node:, var_name:, result:, relation:)
        super(node: node)
        @var_name = var_name
        @result = result
        @relation = relation
      end

      include ResultPrinter

      def to_s
        "#{location_to_str}: IncompatibleAnnotation: var_name=#{var_name}, #{relation}"
      end
    end

    class IncompatibleTypeCase < Base
      attr_reader :var_name
      attr_reader :result
      attr_reader :relation

      def initialize(node:, var_name:, result:, relation:)
        super(node: node)
        @var_name = var_name
        @result = result
        @relation = relation
      end

      include ResultPrinter

      def to_s
        "#{location_to_str}: IncompatibleTypeCase: var_name=#{var_name}, #{relation}"
      end
    end

    class ElseOnExhaustiveCase < Base
      def initialize(node:, type:)
        def to_s
          "#{location_to_str}: ElseOnExhaustiveCase: type=#{type}"
        end
      end
    end

    class UnexpectedSplat < Base
      attr_reader :type

      def initialize(node:, type:)
        super(node: node)
        @type = type
      end

      def to_s
        "#{location_to_str}: UnexpectedSplat: type=#{type}"
      end
    end

    class IncompatibleTuple < Base
      attr_reader :expected_tuple
      include ResultPrinter

      def initialize(node:, expected_tuple:, result:)
        super(node: node)
        @result = result
        @expected_tuple = expected_tuple
      end

      def to_s
        "#{location_to_str}: IncompatibleTuple: expected_tuple=#{expected_tuple}"
      end
    end
  end
end
