module Steep
  module Drivers
    class Checkfile
      LSP = LanguageServer::Protocol

      attr_reader :stdout
      attr_reader :stderr
      attr_reader :command_line_args
      attr_accessor :all_ruby, :all_rbs
      attr_reader :stdin_input
      attr_reader :jobs_option

      include Utils::DriverHelper

      def initialize(stdout:, stderr:)
        @stdout = stdout
        @stderr = stderr
        @command_line_args = []

        @all_rbs = false
        @all_ruby = false
        @stdin_input = {}

        @jobs_option = Utils::JobsOption.new()
      end

      def run
        return 0 if command_line_args.empty? && !all_rbs && !all_ruby && stdin_input.empty?

        project = load_config()

        client_read, server_write = IO.pipe
        server_read, client_write = IO.pipe

        client_reader = LanguageServer::Protocol::Transport::Io::Reader.new(client_read)
        client_writer = LanguageServer::Protocol::Transport::Io::Writer.new(client_write)

        server_reader = LanguageServer::Protocol::Transport::Io::Reader.new(server_read)
        server_writer = LanguageServer::Protocol::Transport::Io::Writer.new(server_write)

        # @type var target_paths: Set[Pathname]
        target_paths = Set[]
        # @type var signature_paths: Set[Pathname]
        signature_paths = Set[]

        loader = Services::FileLoader.new(base_dir: project.base_dir)
        project.targets.each do |target|
          ruby_patterns =
            case
            when all_ruby
              []
            when command_line_args.empty?
              nil
            else
              command_line_args
            end

          if ruby_patterns
            loader.each_path_in_patterns(target.source_pattern, ruby_patterns) do |path|
              target_paths << path
            end
          end

          rbs_patterns =
            case
            when all_rbs
              []
            when command_line_args.empty?
              nil
            else
              command_line_args
            end

          if rbs_patterns
            loader.each_path_in_patterns(target.signature_pattern, rbs_patterns) do |path|
              signature_paths << path
            end
          end
        end

        stdin_input.each_key do |path|
          case ts = project.targets_for_path(path)
          when Array
            signature_paths << path
          when Project::Target
            target_paths << path
          end
        end

        files = target_paths + signature_paths

        count =
          if jobs_option.jobs_count
            jobs_option.jobs_count
          else
            [
              files.size + 2,
              jobs_option.default_jobs_count
            ].min || raise
          end

        Steep.logger.info { "Starting #{count} workers for #{files.size} files..." }

        typecheck_workers = Server::WorkerProcess.start_typecheck_workers(
          steepfile: project.steepfile_path,
          args: [],
          delay_shutdown: true,
          steep_command: jobs_option.steep_command,
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
          Thread.current.abort_on_exception = true
          master.start()
        end

        Steep.logger.info { "Initializing server" }
        initialize_id = request_id()
        client_writer.write({ method: :initialize, id: initialize_id, params: {} })
        wait_for_response_id(reader: client_reader, id: initialize_id)

        stdin_input.each do |path, content|
          uri = PathHelper.to_uri(project.absolute_path(path))

          master.broadcast_notification(
            {
              method: "textDocument/didChange",
              params: {
              textDocument: { uri: uri, version: 0 },
              contentChanges: [{ text: content }]
              }
            }
          )
          master.broadcast_notification(
            {
              method: "textDocument/didSave",
              params: {
                textDocument: { uri: uri }
              }
            }
          )
        end

        ping_guid = master.fresh_request_id()
        client_writer.write({ method: "$/ping", id: ping_guid, params: {} })
        wait_for_response_id(reader: client_reader, id: ping_guid)

        request_guid = master.fresh_request_id()
        request = Server::Master::TypeCheckRequest.new(guid: request_guid)

        target_paths.each do |path|
          request.code_paths << project.absolute_path(path)
        end
        signature_paths.each do |path|
          request.signature_paths << project.absolute_path(path)
        end

        master.start_type_check(request, last_request: nil, start_progress: true)

        Steep.logger.info { "Starting type checking: #{request_guid}" }

        error_messages = [] #: Array[String]
        client_reader.read do |response|
          case
          when response[:method] == "textDocument/publishDiagnostics"
            params = response[:params]

            if path = PathHelper.to_pathname(params[:uri])
              stdout.puts(
                {
                  path: project.relative_path(path).to_s,
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
