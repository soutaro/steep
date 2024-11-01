module Steep
  module Drivers
    class Validate
      LSP = LanguageServer::Protocol

      attr_reader :stdout
      attr_reader :stderr
      attr_reader :targets
      attr_reader :command_line_patterns
      attr_reader :jobs_option

      include Utils::DriverHelper

      def initialize(stdout:, stderr:)
        @stdout = stdout
        @stderr = stderr
        @jobs_option = Utils::JobsOption.new()
        @targets = []
        @command_line_patterns = []
      end

      def active_target?(target)
        targets.empty? || targets.include?(target.name)
      end

      def run
        project = load_config()

        stdout.puts Rainbow("# Validating RBS files:").bold
        stdout.puts

        client_read, server_write = IO.pipe
        server_read, client_write = IO.pipe

        client_reader = LSP::Transport::Io::Reader.new(client_read)
        client_writer = LSP::Transport::Io::Writer.new(client_write)

        server_reader = LSP::Transport::Io::Reader.new(server_read)
        server_writer = LSP::Transport::Io::Writer.new(server_write)

        typecheck_workers = Server::WorkerProcess.start_typecheck_workers(
          steepfile: project.steepfile_path,
          args: command_line_patterns,
          delay_shutdown: true,
          steep_command: jobs_option.steep_command,
          count: jobs_option.jobs_count_value
        )

        master = Server::Master.new(
          project: project,
          reader: server_reader,
          writer: server_writer,
          interaction_worker: nil,
          typecheck_workers: typecheck_workers,
          strategy: :cli
        )
        master.typecheck_automatically = false
        master.commandline_args.push(*command_line_patterns)

        main_thread = Thread.start do
          Thread.current.abort_on_exception = true
          master.start()
        end

        Steep.logger.info { "Initializing server" }
        initialize_id = request_id()
        client_writer.write({ method: :initialize, id: initialize_id, params: DEFAULT_CLI_LSP_INITIALIZE_PARAMS })
        wait_for_response_id(reader: client_reader, id: initialize_id)

        params = { library_paths: [], signature_paths: [], code_paths: [] } #: Server::CustomMethods::TypeCheck::params

        file_loader = Services::FileLoader.new(base_dir: project.base_dir)
        project.targets.each do |target|
          if active_target?(target)
            load_files(file_loader, target, command_line_patterns, params: params)
          end
        end

        Steep.logger.info { "Starting validating #{params[:signature_paths].size} RBS signatures..." }

        request_guid = SecureRandom.uuid
        Steep.logger.info { "Starting validation: #{request_guid}" }
        client_writer.write(Server::CustomMethods::TypeCheck.request(request_guid, params))

        diagnostic_notifications = [] #: Array[LanguageServer::Protocol::Interface::PublishDiagnosticsParams]
        error_messages = [] #: Array[String]

        response = wait_for_response_id(reader: client_reader, id: request_guid) do |message|
          case
          when message[:method] == "textDocument/publishDiagnostics"
            ds = message[:params][:diagnostics]
            # ds.select! {|d| keep_diagnostic?(d, severity_level: severity_level) }
            if ds.empty?
              stdout.print "."
            else
              stdout.print "F"
            end
            diagnostic_notifications << message[:params]
            stdout.flush
          when message[:method] == "window/showMessage"
            # Assuming ERROR message means unrecoverable error.
            message = message[:params]
            if message[:type] == LSP::Constant::MessageType::ERROR
              error_messages << message[:message]
            end
          end
        end

        Steep.logger.info { "Finished validation: #{response.inspect}" }

        Steep.logger.info { "Shutting down..." }

        shutdown_exit(reader: client_reader, writer: client_writer)
        main_thread.join()

        stdout.puts
        stdout.puts

        if error_messages.empty?
          print_result(project: project, notifications: diagnostic_notifications)
        else
          stdout.puts Rainbow("Unexpected error reported. 🚨").red.bold
          return 1
        end
      rescue Errno::EPIPE => error
        stdout.puts Rainbow("Steep shutdown with an error: #{error.inspect}").red.bold
        return 1
      end

      def load_files(loader, target, command_line_patterns, params:)
        if command_line_patterns.empty?
          target.new_env_loader.each_dir do |_, dir|
            RBS::FileFinder.each_file(dir, skip_hidden: true) do |path|
              params[:library_paths] << [target.name.to_s, path.to_s]
            end
          end
        end

        loader.each_path_in_patterns(target.signature_pattern, command_line_patterns) do |path|
          params[:signature_paths] << [target.name.to_s, target.project.absolute_path(path).to_s]
        end

        target.project.targets.each do |project_target|
          next if project_target == target
          next if project_target.unreferenced

          loader.each_path_in_patterns(target.signature_pattern, command_line_patterns) do |path|
            params[:signature_paths] << [target.name.to_s, target.project.absolute_path(path).to_s]
          end
        end
      end

      def print_result(project:, notifications:)
        if notifications.all? {|notification| notification[:diagnostics].empty? }
          emoji = %w(🫖 🫖 🫖 🫖 🫖 🫖 🫖 🫖 🍵 🧋 🧉).sample
          files = notifications.size
          stdout.puts Rainbow("Successfully validated #{files} #{"file".pluralize(files)}. #{emoji}").green.bold
          0
        else
          errors = notifications.reject {|notification| notification[:diagnostics].empty? }
          total = errors.sum {|notification| notification[:diagnostics].size }

          errors.each do |notification|
            path = Steep::PathHelper.to_pathname(notification[:uri]) or raise
            buffer = RBS::Buffer.new(name: project.relative_path(path), content: path.read)
            printer = DiagnosticPrinter.new(buffer: buffer, stdout: stdout)

            notification[:diagnostics].each do |diag|
              printer.print(diag)
              stdout.puts
            end
          end

          stdout.puts Rainbow("Detected #{total} #{"problem".pluralize(total)} from #{errors.size} #{"file".pluralize(errors.size)}").red.bold
          1
        end
      end
    end
  end
end
