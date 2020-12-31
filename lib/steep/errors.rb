module Steep
  module Errors
    class Base
      attr_reader :node

      def initialize(node:)
        @node = node
      end

      def location_to_str
        file = Rainbow(node.loc.expression.source_buffer.name).cyan
        line = Rainbow(node.loc.first_line).bright
        column = Rainbow(node.loc.column).bright
        "#{file}:#{line}:#{column}"
      end

      def format_message(message, class_name: self.class.name.split("::").last)
        if message.empty?
          "#{location_to_str}: #{Rainbow(class_name).red}"
        else
          "#{location_to_str}: #{Rainbow(class_name).red}: #{message}"
        end
      end

      def print_to(io)
        source = node.loc.expression.source
        io.puts "#{to_s} (#{Rainbow(source.split(/\n/).first).blue})"
      end
    end

    module ResultPrinter
      def print_result_to(io, level: 2)
        printer = Drivers::TracePrinter.new(io)
        printer.print result.trace, level: level
        io.puts "==> #{result.error.message}"
      end

      def print_to(io)
        super
        print_result_to io
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
        format_message "receiver=#{receiver_type}, expected=#{expected}, actual=#{actual}"
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
        format_message "expected=#{expected}, actual=#{actual}"
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
        format_message "type=#{type}, method=#{method}", class_name: "NoMethodError"
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
        format_message "expected=#{expected}, actual=#{actual}"
      end
    end

    class UnexpectedBlockGiven < Base
      attr_reader :method_type

      def initialize(node:, method_type:)
        super(node: node)
        @method_type = method_type
      end

      def to_s
        format_message "method_type=#{method_type}"
      end
    end

    class RequiredBlockMissing < Base
      attr_reader :method_type

      def initialize(node:, method_type:)
        super(node: node)
        @method_type = method_type
      end

      def to_s
        format_message "method_type=#{method_type}"
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
        format_message "expected=#{expected}, actual=#{actual}"
      end
    end

    class BlockBodyTypeMismatch < Base
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
        format_message "expected=#{expected}, actual=#{actual}"
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
        format_message "expected=#{expected}, actual=#{actual}"
      end
    end

    class UnexpectedJump < Base
      def to_s
        format_message ""
      end
    end

    class UnexpectedJumpValue < Base
      def to_s
        format_message ""
      end
    end

    class MethodArityMismatch < Base
      def to_s
        format_message "method=#{node.children[0]}"
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
        format_message "interface_method=#{interface_method.type_name}.#{interface_method.name}, annotation_method=#{annotation_method.name}"
      end
    end

    class MethodDefinitionWithOverloading < Base
      attr_reader :method

      def initialize(node:, method:)
        super(node: node)
        @method = method
      end

      def to_s
        format_message "method=#{method.name}, types=#{method.types.join(" | ")}"
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
        format_message "method_type=#{method_type.return_type}, annotation_type=#{annotation_type}"
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
        format_message "method=#{method}, expected=#{expected}, actual=#{actual}"
      end
    end

    class UnexpectedYield < Base
      def to_s
        format_message ""
      end
    end

    class UnexpectedSuper < Base
      attr_reader :method

      def initialize(node:, method:)
        super(node: node)
        @method = method
      end

      def to_s
        format_message "method=#{method}"
      end
    end

    class IncompatibleZuper < Base
      attr_reader :method

      def initialize(node:, method:)
        super(node: node)
        @method = method
      end

      def to_s
        format_message "method=#{method}"
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
        format_message "module=#{module_name}, method=#{method}"
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
        format_message "module=#{module_name}, method=#{method_name}"
      end
    end

    class UnknownConstantAssigned < Base
      attr_reader :type

      def initialize(node:, type:)
        super(node: node)
        @type = type
      end

      def to_s
        format_message "type=#{type}"
      end
    end

    class FallbackAny < Base
      def initialize(node:)
        @node = node
      end

      def to_s
        format_message ""
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
        format_message "method_type=#{method_type}, constraint=#{sub_type} <: '#{var} <: #{super_type}"
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
        format_message "var_name=#{var_name}, #{relation}"
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
        format_message "var_name=#{var_name}, #{relation}"
      end
    end

    class ElseOnExhaustiveCase < Base
      attr_reader :type

      def initialize(node:, type:)
        super(node: node)
        @type = type
      end

      def to_s
        format_message "type=#{type}"
      end
    end

    class UnexpectedSplat < Base
      attr_reader :type

      def initialize(node:, type:)
        super(node: node)
        @type = type
      end

      def to_s
        format_message "type=#{type}"
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
        format_message "expected_tuple=#{expected_tuple}"
      end
    end

    class UnexpectedKeyword < Base
      attr_reader :unexpected_keywords

      def initialize(node:, unexpected_keywords:)
        super(node: node)
        @unexpected_keywords = unexpected_keywords
      end

      def to_s
        format_message unexpected_keywords.to_a.join(", ")
      end
    end

    class MissingKeyword < Base
      attr_reader :missing_keywords

      def initialize(node:, missing_keywords:)
        super(node: node)
        @missing_keywords = missing_keywords
      end

      def to_s
        format_message missing_keywords.to_a.join(", ")
      end
    end

    class UnsupportedSyntax < Base
      attr_reader :message

      def initialize(node:, message: nil)
        super(node: node)
        @message = message
      end

      def to_s
        format_message(message || "#{node.type} is not supported")
      end
    end

    class UnexpectedError < Base
      attr_reader :message
      attr_reader :error

      def initialize(node:, error:)
        super(node: node)
        @error = error
        @message = error.message
      end

      def to_s
        format_message <<-MESSAGE
#{error.class}
>> #{message}
        MESSAGE
      end
    end
  end
end
