require "csv"

module Steep
  module Drivers
    class Stats
      attr_reader :stdout
      attr_reader :stderr
      attr_reader :command_line_patterns

      include Utils::DriverHelper

      def initialize(stdout:, stderr:)
        @stdout = stdout
        @stderr = stderr
        @command_line_patterns = []
      end

      def run
        project = load_config()

        loader = Project::FileLoader.new(project: project)
        loader.load_sources(command_line_patterns)
        loader.load_signatures()

        type_check(project)

        stdout.puts(
          CSV.generate do |csv|
            csv << ["Target", "File", "Status", "Typed calls", "Untyped calls", "All calls", "Typed %"]

            project.targets.each do |target|
              case (status = target.status)
              when Project::Target::TypeCheckStatus
                status.type_check_sources.each do |source_file|
                  case source_file.status
                  when Project::SourceFile::TypeCheckStatus
                    typing = source_file.status.typing

                    typed = 0
                    untyped = 0
                    total = 0
                    typing.method_calls.each_value do |call|
                      case call
                      when TypeInference::MethodCall::Typed
                        typed += 1
                      when TypeInference::MethodCall::Untyped
                        untyped += 1
                      end

                      total += 1
                    end

                    csv << format_stats(target, source_file.path, "success", typed, untyped, total)
                  when Project::SourceFile::TypeCheckErrorStatus
                    csv << format_stats(target, source_file.path, "error", 0, 0, 0)
                  else
                    csv << format_stats(target, source_file.path, "unknown (#{source_file.status.class.to_s.split(/::/).last})", 0, 0, 0)
                  end
                end
              end
            end
          end
        )

        0
      end

      def format_stats(target, path, status, typed, untyped, total)
        [
          target.name,
          path.to_s,
          status,
          typed,
          untyped,
          total,
          if total.nonzero?
            format("%.2f", (typed.to_f/total)*100)
          else
            0
          end
        ]
      end
    end
  end
end
