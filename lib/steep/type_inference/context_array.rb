module Steep
  module TypeInference
    class ContextArray
      attr_reader :buffer
      attr_reader :contexts
      attr_reader :range

      def initialize(buffer:, range: 0..buffer.content.size)
        @contexts = Array.new(buffer.content.size + 1)
        @range = range
        @buffer = buffer
      end

      def self.from_source(source:, range: nil)
        content = if source.node
                    source.node.location.expression.source_buffer.source
                  else
                    ""
                  end
        buffer = AST::Buffer.new(name: source.path, content: content)
        new(buffer: buffer, range: range || 0..buffer.content.size)
      end

      def insert_context(range, context:)
        unless self.range === range.begin && self.range === range.end
          raise "Unexpected pos: range=#{self.range}, inserted=#{range}"
        end

        unless contexts[range].all? {|c| c == contexts[range.begin] || c == context }
          raise "Contexts for range on insert should be the same: range=#{range}"
        end

        contexts.fill(context, range)

        self
      end

      def [](index)
        unless range === index
          raise "Index out of range: range=#{range}, index=#{index}"
        end

        contexts[index]
      end

      def at(line:, column:)
        pos = buffer.loc_to_pos([line, column])
        self[pos]
      end

      def merge(subtree)
        offset = subtree.range.begin
        contexts[subtree.range] = subtree.contexts[subtree.range].map!.with_index do |c, i|
          c || contexts[offset + i]
        end
      end
    end
  end
end
