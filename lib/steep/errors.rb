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
