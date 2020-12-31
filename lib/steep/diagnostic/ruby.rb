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
    end
  end
end
