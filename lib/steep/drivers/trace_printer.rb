module Steep
  module Drivers
    class TracePrinter
      attr_reader :io

      def initialize(io)
        @io = io
      end

      def print(trace, level: 0)
        trace.each.with_index do |t, i|
          prefix = " " * (i + level)
          case t[0]
          when :type
            io.puts "#{prefix}#{t[1]} <: #{t[2]}"
          when :method
            io.puts "#{prefix}(#{t[3]}) #{t[1]} <: #{t[2]}"
          when :method_type
            io.puts "#{prefix}#{t[1]} <: #{t[2]}"
          end
        end
      end
    end
  end
end
