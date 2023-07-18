require "csv"

module Steep
  module Drivers
    class Stats
      class CSVPrinter
        attr_reader :io

        def initialize(io:)
          @io = io
        end

        def print(stats_result)
          io.puts(
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
        end
      end

      class TablePrinter
        attr_reader :io

        def initialize(io:)
          @io = io
        end

        def print(stats_result)
          rows = [] #: Array[Array[untyped]]
          stats_result.sort_by {|row| row[:path] }.each do |row|
            if row[:type] == "success"
              rows << [
                row[:target],
                row[:path] + "  ",
                row[:type],
                row[:typed_calls],
                row[:untyped_calls],
                row[:total_calls],
                if row[:total_calls].nonzero?
                  "#{(row[:typed_calls].to_f / row[:total_calls] * 100).to_i}%"
                else
                  "100%"
                end
              ]
            else
              rows << [
                row[:target],
                row[:path],
                row[:type],
                0,
                0,
                0,
                "N/A"
              ]
            end
          end

          table = Terminal::Table.new(
            headings: ["Target", "File", "Status", "Typed calls", "Untyped calls", "All calls", "Typed %"],
            rows: rows
          )
          table.align_column(3, :right)
          table.align_column(4, :right)
          table.align_column(5, :right)
          table.align_column(6, :right)
          table.style = { border_top: false, border_bottom: false, border_y: "", border_i: "" }
          io.puts(table)
        end
      end

      attr_reader :stdout
      attr_reader :stderr
      attr_reader :command_line_patterns
      attr_accessor :format
      attr_reader :jobs_option

      include Utils::DriverHelper

      def initialize(stdout:, stderr:)
        @stdout = stdout
        @stderr = stderr
        @command_line_patterns = []
        @jobs_option = Utils::JobsOption.new()
      end

      def run
        project = load_config()

        stderr.puts Rainbow("# Calculating stats:").bold
        stderr.puts

        client_read, server_write = IO.pipe
        server_read, client_write = IO.pipe

        client_reader = LanguageServer::Protocol::Transport::Io::Reader.new(client_read)
        client_writer = LanguageServer::Protocol::Transport::Io::Writer.new(client_write)

        server_reader = LanguageServer::Protocol::Transport::Io::Reader.new(server_read)
        server_writer = LanguageServer::Protocol::Transport::Io::Writer.new(server_write)

        typecheck_workers = Server::WorkerProcess.start_typecheck_workers(
          steepfile: project.steepfile_path,
          delay_shutdown: true,
          args: command_line_patterns,
          steep_command: jobs_option.steep_command,
          count: jobs_option.jobs_count_value
        )

        master = Server::Master.new(
          project: project,
          reader: server_reader,
          writer: server_writer,
          interaction_worker: nil,
          typecheck_workers: typecheck_workers
        )
        master.typecheck_automatically = false
        master.commandline_args.push(*command_line_patterns)

        main_thread = Thread.start do
          Thread.current.abort_on_exception = true
          master.start()
        end

        initialize_id = request_id()
        client_writer.write({ method: :initialize, id: initialize_id })
        wait_for_response_id(reader: client_reader, id: initialize_id)

        typecheck_guid = SecureRandom.uuid
        client_writer.write({ method: "$/typecheck", params: { guid: typecheck_guid }})
        wait_for_message(reader: client_reader) do |message|
          message[:method] == "$/progress" &&
            message[:params][:token] == typecheck_guid &&
            message[:params][:value][:kind] == "end"
        end

        stats_id = request_id()
        client_writer.write(
          {
            id: stats_id,
            method: "workspace/executeCommand",
            params: { command: "steep/stats", arguments: [] }
          })

        stats_response = wait_for_response_id(reader: client_reader, id: stats_id)
        stats_result = stats_response[:result]

        shutdown_exit(reader: client_reader, writer: client_writer)
        main_thread.join()

        printer = case format
                  when "csv"
                    CSVPrinter.new(io: stdout)
                  when "table"
                    TablePrinter.new(io: stdout)
                  when nil
                    if stdout.tty?
                      TablePrinter.new(io: stdout)
                    else
                      CSVPrinter.new(io: stdout)
                    end
                  else
                    raise ArgumentError.new("Invalid format: #{format}")
                  end

        printer.print(stats_result)

        0
      end
    end
  end
end
