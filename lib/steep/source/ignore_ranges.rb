module Steep
  class Source
    class IgnoreRanges
      attr_reader :all_ignores, :error_ignores, :ignored_ranges, :ignored_lines

      def initialize(ignores:)
        @all_ignores = ignores.sort_by(&:line)
        @error_ignores = []

        @ignored_lines = {}
        @ignored_ranges = []

        last_start = nil #: AST::Ignore::IgnoreStart?

        all_ignores.each do |ignore|
          case ignore
          when AST::Ignore::IgnoreStart
            if last_start
              error_ignores << last_start
            end
            last_start = ignore
          when AST::Ignore::IgnoreEnd
            if last_start
              ignored_ranges << (last_start.line..ignore.line)
              last_start = nil
            else
              error_ignores << ignore
            end
          when AST::Ignore::IgnoreLine
            if last_start
              error_ignores << ignore
            else
              ignored_lines[ignore.line] = ignore
            end
          end
        end

        if last_start
          error_ignores << last_start
        end
      end

      def ignore?(start_line, end_line, code)
        if ignore = ignored_lines.fetch(start_line, nil)
          ignore_code?(ignore, code) and return true
        end

        if start_line != end_line
          if ignore = ignored_lines.fetch(end_line, nil)
            ignore_code?(ignore, code) and return true
          end
        end

        ignored_ranges.any? do |range|
          range.cover?(start_line) && range.cover?(end_line)
        end
      end

      def ignore_code?(line, code)
        case diags = line.ignored_diagnostics
        when Symbol
          true
        else
          diags.any? {|d| code == "Ruby::#{d}" }
        end
      end
    end
  end
end
