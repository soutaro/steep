module Steep
  class Source
    class DirectiveMap
      attr_reader :ignored_ranges

      def initialize(comments)
        @ignored_ranges = build_ignored_ranges(comments)
      end

      def ignored?(error)
        ignored_ranges.any? { |range| range.include?(error) }
      end

      private

      def build_ignored_ranges(comments)
        ignored_ranges = []  #: Array[IgnoredRange]
        stack = []  #: Array[DirectiveComment]
        comments.each do |comment|
          directive_comment = DirectiveComment.new(comment)
          if directive_comment.valid?
            if directive_comment.start?
              stack << directive_comment
            else
              from = stack.pop
              ignored_ranges << IgnoredRange.new(from: from, to: directive_comment) if from
            end
          end
        end

        stack.each do |from|
          ignored_ranges << IgnoredRange.new(from: from, to: nil)
        end

        ignored_ranges
      end
    end
  end
end
