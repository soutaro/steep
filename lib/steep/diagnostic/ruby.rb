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
    end
  end
end
