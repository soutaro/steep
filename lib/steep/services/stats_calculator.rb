module Steep
  module Services
    class StatsCalculator
      class SuccessStats < Struct.new(:target, :path, :typed_calls_count, :untyped_calls_count, :error_calls_count, keyword_init: true)
        def as_json
          {
            type: "success",
            target: target.name.to_s,
            path: path.to_s,
            typed_calls: typed_calls_count,
            untyped_calls: untyped_calls_count,
            error_calls: error_calls_count,
            total_calls: typed_calls_count + untyped_calls_count + error_calls_count
          }
        end
      end
      class ErrorStats < Struct.new(:target, :path, keyword_init: true)
        def as_json
          {
            type: "error",
            target: target.name.to_s,
            path: path.to_s
          }
        end
      end

      def self.count_calls(typing)
        typed = 0
        untyped = 0
        errors = 0

        typing.method_calls.each_value do |call|
          case call
          when TypeInference::MethodCall::Typed
            typed += 1
          when TypeInference::MethodCall::Untyped
            untyped += 1
          when TypeInference::MethodCall::Error, TypeInference::MethodCall::NoMethodError
            errors += 1
          else
            raise
          end
        end

        { typed_calls: typed, untyped_calls: untyped, error_calls: errors }
      end
    end
  end
end
