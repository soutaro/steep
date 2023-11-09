module Steep
  class Source
    class DirectiveComment
      DIAGNOSTIC_NAME_PATTERN = '[A-Z]\w+'
      DIAGNOSTICS_NAME_PATTERN = "(?:#{DIAGNOSTIC_NAME_PATTERN} , )*#{DIAGNOSTIC_NAME_PATTERN}"
      DIRECTIVE_COMMENT_REGEXP = Regexp.new(
        "# steep:ignore\\b (all|end|#{DIAGNOSTICS_NAME_PATTERN})"
          .gsub(' ', '\s*')
      )

      attr_reader :comment, :args, :location

      def initialize(comment)
        @comment = comment
        @args = parse_args(comment)
        @location = comment.location
      end

      def valid?
        comment.text.match? DIRECTIVE_COMMENT_REGEXP
      end

      def all?
        args == ["all"]
      end

      def start?
        !end?
      end

      def end?
        args == ["end"]
      end

      def diagnostic_names
        all? || end? ? [] : args
      end

      private

      def parse_args(comment)
        arguments = comment.text.match(DIRECTIVE_COMMENT_REGEXP).to_a[1]
        arguments ? arguments.split(",").map(&:strip) : []
      end
    end
  end
end
