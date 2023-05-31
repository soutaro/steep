module Steep
  module TypeInference
    class ContextArray
      class Entry
        attr_reader :range, :context, :sub_entries

        def initialize(range:, context:)
          @range = range
          @context = context
          @sub_entries = Set[].compare_by_identity
        end
      end

      attr_reader :buffer
      attr_reader :root

      def initialize(buffer:, context:, range: 0..buffer.content.size)
        @buffer = buffer
        @root = Entry.new(range: range, context: context)
      end

      def range
        root.range
      end

      def self.from_source(source:, range: nil, context:)
        content = if source.node
                    source.node.location.expression.source_buffer.source
                  else
                    ""
                  end
        buffer = RBS::Buffer.new(name: source.path, content: content)
        range ||= 0..buffer.content.size
        new(buffer: buffer, context: context, range: range)
      end

      def insert_context(range, context:, entry: self.root)
        entry.sub_entries.each do |sub|
          next if sub.range.begin <= range.begin && range.end <= sub.range.end
          next if range.begin <= sub.range.begin && sub.range.end <= range.end
          next if range.end <= sub.range.begin
          next if sub.range.end <= range.begin

          Steep.logger.error { "Range crossing: sub range=#{sub.range}, new range=#{range}" }
          raise
        end

        sup = entry.sub_entries.find do |sub|
          sub.range.begin < range.begin && range.end <= sub.range.end
        end

        if sup
          insert_context(range, context: context, entry: sup)
        else
          subs = entry.sub_entries.select do |sub|
            range.begin < sub.range.begin && sub.range.end <= range.end
          end

          new_entry = Entry.new(range: range, context: context)
          entry.sub_entries.subtract(subs)
          new_entry.sub_entries.merge(subs)
          entry.sub_entries << new_entry
        end
      end

      def each_entry(&block)
        if block
          es = [root]

          while e = es.pop
            es.push(*e.sub_entries.to_a)

            yield e
          end
        else
          enum_for :each_entry
        end
      end

      def context_at(index, entry: self.root)
        return nil if index < entry.range.begin || entry.range.end < index

        sub = entry.sub_entries.find do |sub|
          sub.range.begin <= index && index <= sub.range.end
        end

        if sub
          context_at(index, entry: sub)
        else
          entry.context
        end
      end

      def [](index)
        context_at(index)
      end

      def at(line:, column:)
        pos = buffer.loc_to_pos([line, column])
        self[pos]
      end

      def merge(subtree)
        subtree.each_entry do |entry|
          if entry.context
            insert_context entry.range, context: entry.context
          end
        end
      end
    end
  end
end
