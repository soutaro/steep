module Steep
  module AST
    module Ignore
      class BufferScanner
        attr_reader :scanner, :location

        def initialize(location)
          @location = location

          @scanner = StringScanner.new(location.source)
        end

        def offset
          @location.start_pos
        end

        def charpos
          scanner.charpos + offset
        end

        def scan(regexp)
          if matched = scanner.scan(regexp)
            end_pos = charpos()
            begin_pos = end_pos - matched.size
            RBS::Location.new(location.buffer, begin_pos, end_pos)
          end
        end

        def skip(regexp)
          scanner.skip(regexp)
        end

        def eos?
          scanner.eos?
        end
      end

      class IgnoreStart
        attr_reader :comment, :location

        def initialize(comment, location)
          @comment = comment
          @location = location
        end

        def line
          location.start_line
        end
      end

      class IgnoreEnd
        attr_reader :comment, :location

        def initialize(comment, location)
          @comment = comment
          @location = location
        end

        def line
          location.start_line
        end
      end

      class IgnoreLine
        attr_reader :comment, :location, :raw_diagnostics

        def initialize(comment, diagnostics, location)
          @comment = comment
          @raw_diagnostics = diagnostics
          @location = location
        end

        def line
          location.start_line
        end

        def ignored_diagnostics
          if raw_diagnostics.empty?
            return :all
          end

          if raw_diagnostics.size == 1 && raw_diagnostics.fetch(0).source == "all"
            return :all
          end

          raw_diagnostics.map do |diagnostic|
            name = diagnostic[:name].source
            name.gsub(/\ARuby::/, "")
          end
        end
      end

      def self.parse(comment, buffer)
        return unless comment.inline?

        begin_pos = buffer.loc_to_pos([comment.loc.line, comment.loc.column])
        end_pos = buffer.loc_to_pos([comment.loc.last_line, comment.loc.last_column])
        comment_location = RBS::Location.new(buffer, begin_pos, end_pos)
        scanner = BufferScanner.new(comment_location)

        scanner.scan(/#/)
        scanner.skip(/\s*/)

        case
        when loc = scanner.scan(/steep:ignore:start\b/)
          scanner.skip(/\s*/)
          return unless scanner.eos?

          IgnoreStart.new(comment, loc)
        when loc = scanner.scan(/steep:ignore:end\b/)
          scanner.skip(/\s*/)
          return unless scanner.eos?

          IgnoreEnd.new(comment, loc)
        when keyword_loc = scanner.scan(/steep:ignore\b/)
          # @type var diagnostics: IgnoreLine::diagnostics
          diagnostics = []

          scanner.skip(/\s*/)

          while true
            name = scanner.scan(/[A-Z]\w*/) or break
            scanner.skip(/\s*/)
            comma = scanner.scan(/,/)
            scanner.skip(/\s*/)

            diagnostic = RBS::Location.new(buffer, name.start_pos, comma&.end_pos || name.end_pos) #: IgnoreLine::diagnostic
            diagnostic.add_required_child(:name, name.range)
            diagnostic.add_optional_child(:following_comma, comma&.range)
            diagnostics << diagnostic

            break unless comma
          end

          return unless scanner.eos?

          loc = RBS::Location.new(
            buffer,
            keyword_loc.start_pos,
            diagnostics.last&.end_pos || keyword_loc.end_pos
          )
          IgnoreLine.new(comment, diagnostics, loc)
        end
      end
    end
  end
end
