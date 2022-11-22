module Steep
  module Diagnostic
    module Helper
      def error_name
        name = self.class.name or raise
        name.split(/::/).last or raise
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
