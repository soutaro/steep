module Steep
  module Diagnostic
    module ResultPrinter2
      def result_line(result)
        case result
        when Subtyping::Result::Failure
          case result.error
          when Subtyping::Result::Failure::UnknownPairError
            nil
          when Subtyping::Result::Failure::UnsatisfiedConstraints
            "Unsatisfied constraints: #{result.relation}"
          when Subtyping::Result::Failure::MethodMissingError
            "Method `#{result.error.name}` is missing"
          when Subtyping::Result::Failure::BlockMismatchError
            "Incomaptible block: #{result.relation}"
          when Subtyping::Result::Failure::ParameterMismatchError
            if result.relation.params?
              "Incompatible arity: #{result.relation.super_type} and #{result.relation.sub_type}"
            else
              "Incompatible arity: #{result.relation}"
            end
          when Subtyping::Result::Failure::PolyMethodSubtyping
            "Unsupported polymorphic method comparison: #{result.relation}"
          when Subtyping::Result::Failure::SelfBindingMismatch
            "Incompatible block self type: #{result.relation}"
          end
        else
          result.relation.to_s
        end
      end

      def detail_lines
        lines = StringIO.new.tap do |io|
          failure_path = result.failure_path || []
          failure_path.reverse_each.filter_map do |result|
            result_line(result)
          end.each.with_index(1) do |message, index|
            io.puts "#{"  " * (index)}#{message}"
          end
        end.string.chomp

        unless lines.empty?
          lines
        end
      end
    end
  end
end
