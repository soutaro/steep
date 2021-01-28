module Steep
  module Diagnostic
    module Helper
      def location_to_str
        file = Rainbow(location.source_buffer.name).cyan
        line = Rainbow(location.first_line).bright
        column = Rainbow(location.column).bright
        "#{file}:#{line}:#{column}"
      end

      def error_name
        self.class.name.split(/::/).last
      end

      def to_s
        "#{location_to_str}: #{header_line}"
      end

      def full_message
        if detail = detail_lines
          "#{header_line}\n#{detail}"
        else
          "#{header_line}"
        end
      end
    end
  end
end
