module Steep
  module Services
    class ContentChange
      class Position
        attr_reader :line, :column

        def initialize(line:, column:)
          @line = line
          @column = column
        end

        def ==(other)
          other.is_a?(Position) && other.line == line && other.column == column
        end

        alias eql? ==

        def hash
          self.class.hash ^ line ^ column
        end
      end

      attr_reader :range, :text

      def initialize(range: nil, text:)
        @range = range
        @text = text
      end

      def ==(other)
        other.is_a?(ContentChange) && other.range == range && other.text == text
      end

      alias eql? ==

      def hash
        self.class.hash ^ range.hash ^ text.hash
      end

      def self.string(string)
        new(text: string)
      end

      def apply_to(text)
        if range
          text = text.dup
          start_pos, end_pos = range

          buf = RBS::Buffer.new(name: :_, content: text)
          start_pos = buf.loc_to_pos([start_pos.line, start_pos.column])
          end_pos = buf.loc_to_pos([end_pos.line, end_pos.column])

          text[start_pos...end_pos] = self.text
          text
        else
          self.text
        end
      end
    end
  end
end
