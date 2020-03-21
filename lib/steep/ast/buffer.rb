module Steep
  module AST
    class Buffer
      attr_reader :name
      attr_reader :content
      attr_reader :lines
      attr_reader :ranges

      def initialize(name:, content:)
        @name = name
        @content = content

        @lines = content.split(/\n/, -1)

        @ranges = []
        offset = 0
        lines.each.with_index do |line, index|
          if index == lines.size - 1
            ranges << (offset..offset)
          else
            size = line.size
            range = offset..(offset+size)
            ranges << range
            offset += size+1
          end
        end
      end

      def pos_to_loc(pos)
        index = ranges.bsearch_index do |range|
          pos <= range.end
        end

        if index
          [index + 1, pos - ranges[index].begin]
        else
          [1, pos]
        end
      end

      def loc_to_pos(loc)
        line, column = loc
        ranges[line - 1].begin + column
      end

      def source(range)
        content[range]
      end
    end
  end
end
