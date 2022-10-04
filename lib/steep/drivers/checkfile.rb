module Steep
  module Drivers
    class Checkfile
      LSP = LanguageServer::Protocol

      attr_reader :stdout
      attr_reader :stderr
      attr_reader :command_line_args

      include Utils::DriverHelper
      include Utils::JobsCount

      def initialize(stdout:, stderr:)
        @stdout = stdout
        @stderr = stderr
        @command_line_args = []
      end

      def run
        project = load_config()

        client_read, server_write = IO.pipe
        server_read, client_write = IO.pipe

        client_reader = LanguageServer::Protocol::Transport::Io::Reader.new(client_read)
        client_writer = LanguageServer::Protocol::Transport::Io::Writer.new(client_write)

        server_reader = LanguageServer::Protocol::Transport::Io::Reader.new(server_read)
        server_writer = LanguageServer::Protocol::Transport::Io::Writer.new(server_write)

        files = command_line_args

        count =
          if files.size >= jobs_count
            jobs_count
          else
            files.size
          end

        typecheck_workers = Server::WorkerProcess.spawn_typecheck_workers(
          steepfile: project.steepfile_path,
          args: [],
          delay_shutdown: true,
          steep_command: steep_command,
          count: count
        )

        master = Server::Master.new(
          project: project,
          reader: server_reader,
          writer: server_writer,
          interaction_worker: nil,
          typecheck_workers: typecheck_workers
        )
        master.typecheck_automatically = false

        main_thread = Thread.start do
          master.start()
        end
        main_thread.abort_on_exception = true

        Steep.logger.info { "Initializing server" }
        initialize_id = request_id()
        client_writer.write({ method: :initialize, id: initialize_id, params: {} })
        wait_for_response_id(reader: client_reader, id: initialize_id)

        request_guid = SecureRandom.uuid
        request = Server::Master::TypeCheckRequest.new(guid: request_guid)

        files.each do |path|
          request.code_paths << project.absolute_path(Pathname(path))
        end

        master.start_type_check(request, last_request: nil, start_progress: true)

        Steep.logger.info { "Starting type checking: #{request_guid}" }

        diagnostic_notifications = []
        error_messages = []
        client_reader.read do |response|
          case
          when response[:method] == "textDocument/publishDiagnostics"
            params = response[:params]

            if path = PathHelper.to_pathname(params[:uri])
              stdout.puts(
                {
                  path: path.to_s,
                  diagnostics: params[:diagnostics]
                }.to_json
              )
            end
          when response[:method] == "window/showMessage"
            # Assuming ERROR message means unrecoverable error.
            message = response[:params]
            if message[:type] == LSP::Constant::MessageType::ERROR
              error_messages << message[:message]
            end
          when response[:method] == "$/progress"
            if response[:params][:token] == request_guid
              if response[:params][:value][:kind] == "end"
                break
              end
            end
          end
        end

        Steep.logger.info { "Shutting down..." }

        shutdown_exit(reader: client_reader, writer: client_writer)
        main_thread.join()

        0
      end
    end
  end
end
