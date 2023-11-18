module Steep
  class Source
    class IgnoredRange
      attr_reader :from, :to

      def initialize(from:, to:)
        @from = from
        @to = to
      end

      def include?(error)
        line = case error.location
               when Parser::Source::Range
                 error.location.line
               when RBS::Location
                 error.location.start_line
               else
                 0
               end

        cover?(line: line) && match?(type: error)
      end

      private

      def cover?(line:)
        (from.location.line..to&.location&.line).cover?(line)
      end

      def match?(type:)
        class_name = type.class.name.to_s.split('::').last
        @from.all? || @from.diagnostic_names.include?(class_name)
      end
    end
  end
end
