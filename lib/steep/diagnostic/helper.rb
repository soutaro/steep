module Steep
  module Diagnostic
    module Helper
      def error_name
        self.class.name.split(/::/).last
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
