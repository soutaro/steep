module Steep
  module TypeInference
    class PatternMatching
      class Clause < Struct.new(:truthy_result, :falsy_result, :clause_type)
      end

      attr_reader :initial, :clauses, :last_result

      def initialize(initial:, initial_result:)
        @initial = initial
        @last_result = initial_result
        @clauses = []
      end

      def match_clause(pattern)
        case pattern.type
        when :array_pattern
        when :match_as
        when :const_pattern
        else

        end
      end

      def else_clause()

      end

      def result

      end
    end
  end
end
