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

        stderr.puts Rainbow("# Calculating stats:").bold
        stderr.puts

        client_read, server_write = IO.pipe
        server_read, client_write = IO.pipe

        client_reader = LanguageServer::Protocol::Transport::Io::Reader.new(client_read)
        client_writer = LanguageServer::Protocol::Transport::Io::Writer.new(client_write)

        server_reader = LanguageServer::Protocol::Transport::Io::Reader.new(server_read)
        server_writer = LanguageServer::Protocol::Transport::Io::Writer.new(server_write)

        interaction_worker = Server::WorkerProcess.spawn_worker(:interaction, name: "interaction", steepfile: project.steepfile_path, delay_shutdown: true)
        typecheck_workers = Server::WorkerProcess.spawn_typecheck_workers(steepfile: project.steepfile_path, delay_shutdown: true, args: command_line_patterns)

        master = Server::Master.new(
          project: project,
          reader: server_reader,
          writer: server_writer,
          interaction_worker: interaction_worker,
          typecheck_workers: typecheck_workers
        )

        main_thread = Thread.start do
          master.start()
        end
        main_thread.abort_on_exception = true

        client_writer.write({ method: :initialize, id: 0 })

        stats_id = -1
        client_writer.write(
          {
            id: stats_id,
            method: "workspace/executeCommand",
            params: { command: "steep/stats", arguments: [] }
          })

        stats_result = []
        client_reader.read do |response|
          if response[:id] == stats_id
            stats_result.push(*response[:result])
            break
          end
        end

        shutdown_id = -2
        client_writer.write({ method: :shutdown, id: shutdown_id })

        client_reader.read do |response|
          if response[:id] == shutdown_id
            break
          end
        end

        client_writer.write({ method: "exit" })
        main_thread.join()

        stdout.puts(
          CSV.generate do |csv|
            csv << ["Target", "File", "Status", "Typed calls", "Untyped calls", "All calls", "Typed %"]
            stats_result.each do |row|
              if row[:type] == "success"
                csv << [
                  row[:target],
                  row[:path],
                  row[:type],
                  row[:typed_calls],
                  row[:untyped_calls],
                  row[:total_calls],
                  if row[:total_calls].nonzero?
                    (row[:typed_calls].to_f / row[:total_calls] * 100).to_i
                  else
                    100
                  end
                ]
              else
                csv << [
                  row[:target],
                  row[:path],
                  row[:type],
                  0,
                  0,
                  0,
                  0
                ]
              end
            end
          end
        )
        #
        # type_check(project)
        #
        # stdout.puts(
        #   CSV.generate do |csv|
        #     csv << ["Target", "File", "Status", "Typed calls", "Untyped calls", "All calls", "Typed %"]
        #
        #     project.targets.each do |target|
        #       case (status = target.status)
        #       when Project::Target::TypeCheckStatus
        #         status.type_check_sources.each do |source_file|
        #           case source_file.status
        #           when Project::SourceFile::TypeCheckStatus
        #             typing = source_file.status.typing
        #
        #             typed = 0
        #             untyped = 0
        #             total = 0
        #             typing.method_calls.each_value do |call|
        #               case call
        #               when TypeInference::MethodCall::Typed
        #                 typed += 1
        #               when TypeInference::MethodCall::Untyped
        #                 untyped += 1
        #               end
        #
        #               total += 1
        #             end
        #
        #             csv << format_stats(target, source_file.path, "success", typed, untyped, total)
        #           when Project::SourceFile::TypeCheckErrorStatus
        #             csv << format_stats(target, source_file.path, "error", 0, 0, 0)
        #           else
        #             csv << format_stats(target, source_file.path, "unknown (#{source_file.status.class.to_s.split(/::/).last})", 0, 0, 0)
        #           end
        #         end
        #       end
        #     end
        #   end
        # )

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
