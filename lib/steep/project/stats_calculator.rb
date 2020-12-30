module Steep
  class Project
    class StatsCalculator
      SuccessStats = Struct.new(:target, :path, :typed_calls_count, :untyped_calls_count, :error_calls_count, keyword_init: true) do
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
      ErrorStats = Struct.new(:target, :path, :status, keyword_init: true) do
        def as_json
          {
            type: "error",
            target: target.name.to_s,
            path: path.to_s,
            status: status.class.to_s
          }
        end
      end

      attr_reader :project

      def initialize(project:)
        @project = project
      end

      def calc_stats(target, path)
        source_file = target.source_files[path] or raise

        target.type_check(
          target_sources: [source_file],
          validate_signatures: false
        )

        if target.status.is_a?(Target::TypeCheckStatus)
          case source_file.status
          when SourceFile::TypeCheckStatus
            typing = source_file.status.typing

            typed = 0
            untyped = 0
            errors = 0
            total = 0
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

            SuccessStats.new(
              target: target,
              path: path,
              typed_calls_count: typed,
              untyped_calls_count: untyped,
              error_calls_count: errors
            )
          when SourceFile::TypeCheckErrorStatus, SourceFile::AnnotationSyntaxErrorStatus, SourceFile::ParseErrorStatus
            ErrorStats.new(target: target, path: path, status: source_file.status)
          end
        else
          ErrorStats.new(target: target, path: path, status: target.status)
        end
      end
    end
  end
end
