module Steep
  module Diagnostic
    module Ruby
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
          format_message "lhs_type=#{lhs_type}, rhs_type=#{rhs_type}"
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
          format_message "receiver=#{receiver_type}, method_type=#{method_type}"
        end
      end

      class UnresolvedOverloading < Base
        attr_reader :node
        attr_reader :receiver_type
        attr_reader :method_name
        attr_reader :method_types

        def initialize(node:, receiver_type:, method_name:, method_types:)
          super node: node
          @receiver_type = receiver_type
          @method_name = method_name
          @method_types = method_types
        end

        def to_s
          format_message "receiver=#{receiver_type}, method_name=#{method_name}, method_types=#{method_types.join(" | ")}"
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
    end
  end
end
