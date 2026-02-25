module Steep
  module Drivers
    class Check
      LSP = LanguageServer::Protocol

      attr_reader :stdout
      attr_reader :stderr
      attr_reader :command_line_patterns
      attr_accessor :with_expectations_path
      attr_accessor :save_expectations_path
      attr_accessor :severity_level
      attr_reader :jobs_option
      attr_reader :targets
      attr_reader :active_group_names
      attr_accessor :type_check_code
      attr_accessor :validate_group_signatures
      attr_accessor :validate_project_signatures
      attr_accessor :validate_library_signatures
      attr_accessor :formatter
      attr_accessor :use_daemon

      include Utils::DriverHelper

      def initialize(stdout:, stderr:)
        @stdout = stdout
        @stderr = stderr
        @command_line_patterns = []
        @severity_level = :warning
        @jobs_option = Utils::JobsOption.new()
        @active_group_names = []
        @type_check_code = true
        @validate_group_signatures = true
        @validate_project_signatures = false
        @validate_library_signatures = false
        @formatter = 'code'
        @use_daemon = true
      end

      def active_group?(group)
        return true if active_group_names.empty?

        case group
        when Project::Target
          active_group_names.any? {|target_name, group_name|
            target_name == group.name && (group_name == nil || group_name == true)
          }
        when Project::Group
          active_group_names.any? {|target_name, group_name|
            target_name == group.target.name &&
              (group_name == group.name || group_name == true)
          }
        end
      end

      def run
        if use_daemon
          if Daemon.running?
            Steep.logger.info { "Daemon detected, using server mode" }
            return run_with_server
          elsif Daemon.starting?
            Steep.logger.info { "Daemon is starting, waiting for it to be ready" }
            if wait_for_daemon
              return run_with_server
            else
              stderr.puts Rainbow("Daemon failed to start, falling back to standard mode").yellow
            end
          end
        end

        Steep.logger.info { "Using standard mode" }
        run_standard_check
      end

      def load_files(files, target, group, params:)
        if type_check_code
          files.source_paths.each_group_path(group) do |path, *|
            params[:code_paths] << [target.name.to_s, target.project.absolute_path(path).to_s]
          end
        end
        if validate_group_signatures
          files.signature_paths.each_group_path(group) do |path, *|
            params[:signature_paths] << [target.name.to_s, target.project.absolute_path(path).to_s]
          end
        end
        if validate_project_signatures
          files.signature_paths.each_project_path(except: target) do |path, path_target, *|
            params[:signature_paths] << [path_target.name.to_s, target.project.absolute_path(path).to_s]
          end
          if group.is_a?(Project::Group)
            files.signature_paths.each_target_path(target, except: group) do |path, *|
              params[:signature_paths] << [target.name.to_s, target.project.absolute_path(path).to_s]
            end
          end
        end
        if validate_library_signatures
          files.each_library_path(target) do |path|
            params[:library_paths] << [target.name.to_s, path.to_s]
          end
        end
      end

      def print_expectations(project:, all_files:, expectations_path:, notifications:)
        expectations = Expectations.load(path: expectations_path, content: expectations_path.read)

        expected_count = 0
        unexpected_count = 0
        missing_count = 0

        ns = notifications.each.with_object({}) do |notification, hash| #$ Hash[Pathname, Array[Expectations::Diagnostic]]
          path = project.relative_path(Steep::PathHelper.to_pathname(notification[:uri]) || raise)
          hash[path] = notification[:diagnostics].map do |diagnostic|
            Expectations::Diagnostic.from_lsp(diagnostic)
          end
        end

        all_files.sort.each do |path|
          test = expectations.test(path: path, diagnostics: ns[path] || [])

          buffer = RBS::Buffer.new(name: path, content: path.read)
          printer = DiagnosticPrinter.new(buffer: buffer, stdout: stdout)

          test.each_diagnostics.each do |type, diag|
            case type
            when :expected
              expected_count += 1
            when :unexpected
              unexpected_count += 1
              printer.print(diag.to_lsp, prefix: Rainbow("+ ").green)
            when :missing
              missing_count += 1
              printer.print(diag.to_lsp, prefix: Rainbow("- ").red, source: false)
            end
          end
        end

        if unexpected_count > 0 || missing_count > 0
          stdout.puts

          stdout.puts Rainbow("Expectations unsatisfied:").bold.red
          stdout.puts "  #{expected_count} expected #{"diagnostic".pluralize(expected_count)}"
          stdout.puts Rainbow("  + #{unexpected_count} unexpected #{"diagnostic".pluralize(unexpected_count)}").green
          stdout.puts Rainbow("  - #{missing_count} missing #{"diagnostic".pluralize(missing_count)}").red
          1
        else
          stdout.puts Rainbow("Expectations satisfied:").bold.green
          stdout.puts "  #{expected_count} expected #{"diagnostic".pluralize(expected_count)}"
          0
        end
      end

      def save_expectations(project:, all_files:, expectations_path:, notifications:)
        expectations = if expectations_path.file?
                         Expectations.load(path: expectations_path, content: expectations_path.read)
                       else
                         Expectations.empty()
                       end

        ns = notifications.each.with_object({}) do |notification, hash| #$ Hash[Pathname, Array[Expectations::Diagnostic]]
          path = project.relative_path(Steep::PathHelper.to_pathname(notification[:uri]) || raise)
          hash[path] = notification[:diagnostics].map {|diagnostic| Expectations::Diagnostic.from_lsp(diagnostic) }
        end

        all_files.sort.each do |path|
          ds = ns[path] || []

          if ds.empty?
            expectations.diagnostics.delete(path)
          else
            expectations.diagnostics[path] = ds
          end
        end

        expectations_path.write(expectations.to_yaml)
        stdout.puts Rainbow("Saved expectations in #{expectations_path}...").bold
        0
      end

      def print_result(project:, notifications:)
        if notifications.all? {|notification| notification[:diagnostics].empty? }
          emoji = %w(🫖 🫖 🫖 🫖 🫖 🫖 🫖 🫖 🍵 🧋 🧉).sample
          stdout.puts Rainbow("No type error detected. #{emoji}").green.bold
          0
        else
          errors = notifications.reject {|notification| notification[:diagnostics].empty? }
          total = errors.sum {|notification| notification[:diagnostics].size }

          errors.each do |notification|
            path = Steep::PathHelper.to_pathname(notification[:uri]) or raise
            buffer = RBS::Buffer.new(name: project.relative_path(path), content: path.read)
            printer = DiagnosticPrinter.new(buffer: buffer, stdout: stdout, formatter: formatter)

            notification[:diagnostics].each do |diag|
              printer.print(diag)
              stdout.puts
            end
          end

          stdout.puts Rainbow("Detected #{total} #{"problem".pluralize(total)} from #{errors.size} #{"file".pluralize(errors.size)}").red.bold
          1
        end
      end

      private

      def run_with_server
        project = load_config()

        stdout.puts Rainbow("# Type checking files (server mode):").bold
        stdout.puts

        params = build_typecheck_params(project)

        Steep.logger.info {
          "Server mode: #{params[:code_paths].size} code files, #{params[:signature_paths].size} signatures"
        }

        socket = UNIXSocket.new(Daemon.socket_path)
        reader = LSP::Transport::Io::Reader.new(socket)
        writer = LSP::Transport::Io::Writer.new(socket)

        request_guid = SecureRandom.uuid
        writer.write(Server::CustomMethods::TypeCheck.request(request_guid, params))

        diagnostic_notifications = [] #: Array[LanguageServer::Protocol::Interface::PublishDiagnosticsParams]
        error_messages = [] #: Array[String]

        wait_for_response_id(reader: reader, id: request_guid) do |message|
          case message[:method]
          when "textDocument/publishDiagnostics"
            ds = message[:params][:diagnostics]
            ds.select! { |d| keep_diagnostic?(d, severity_level: severity_level) }
            stdout.print(ds.empty? ? "." : "F")
            diagnostic_notifications << message[:params]
            stdout.flush
          when "window/showMessage"
            if message[:params][:type] == LSP::Constant::MessageType::ERROR
              error_messages << message[:params][:message]
            end
          end
        end

        socket.close

        stdout.puts
        stdout.puts

        print_typecheck_result(project: project, diagnostic_notifications: diagnostic_notifications, error_messages: error_messages)
      rescue Errno::ECONNREFUSED, Errno::ENOENT => e
        stderr.puts "Steep server connection failed (#{e.message}), falling back to normal check"
        run_standard_check
      rescue Errno::EPIPE => error
        stdout.puts Rainbow("Steep server connection lost: #{error.inspect}").red.bold
        1
      end

      def run_standard_check
        project = load_config()

        stdout.puts Rainbow("# Type checking files:").bold
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
          typecheck_workers: typecheck_workers
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

        params = build_typecheck_params(project)

        Steep.logger.info { "Starting type check with #{params[:code_paths].size} Ruby files and #{params[:signature_paths].size} RBS signatures..." }
        Steep.logger.debug { params.inspect }

        request_guid = SecureRandom.uuid
        Steep.logger.info { "Starting type checking: #{request_guid}" }
        client_writer.write(Server::CustomMethods::TypeCheck.request(request_guid, params))

        diagnostic_notifications = [] #: Array[LanguageServer::Protocol::Interface::PublishDiagnosticsParams]
        error_messages = [] #: Array[String]

        response = wait_for_response_id(reader: client_reader, id: request_guid) do |message|
          case
          when message[:method] == "textDocument/publishDiagnostics"
            ds = message[:params][:diagnostics]
            ds.select! {|d| keep_diagnostic?(d, severity_level: severity_level) }
            if ds.empty?
              stdout.print "."
            else
              stdout.print "F"
            end
            diagnostic_notifications << message[:params]
            stdout.flush
          when message[:method] == "window/showMessage"
            message = message[:params]
            if message[:type] == LSP::Constant::MessageType::ERROR
              error_messages << message[:message]
            end
          end
        end

        Steep.logger.info { "Finished type checking: #{response.inspect}" }

        Steep.logger.info { "Shutting down..." }

        shutdown_exit(reader: client_reader, writer: client_writer)
        main_thread.join()

        stdout.puts
        stdout.puts

        print_typecheck_result(project: project, diagnostic_notifications: diagnostic_notifications, error_messages: error_messages)
      rescue Errno::EPIPE => error
        stdout.puts Rainbow("Steep shutdown with an error: #{error.inspect}").red.bold
        return 1
      end

      def print_typecheck_result(project:, diagnostic_notifications:, error_messages:)
        if error_messages.empty?
          loader = Services::FileLoader.new(base_dir: project.base_dir)
          all_files = project.targets.each.with_object(Set[]) do |target, set|
            set.merge(loader.load_changes(target.source_pattern, command_line_patterns, changes: {}).each_key)
            set.merge(loader.load_changes(target.signature_pattern, changes: {}).each_key)
          end.to_a

          case
          when with_expectations_path
            print_expectations(project: project,
                               all_files: all_files,
                               expectations_path: with_expectations_path,
                               notifications: diagnostic_notifications)
          when save_expectations_path
            save_expectations(project: project,
                              all_files: all_files,
                              expectations_path: save_expectations_path,
                              notifications: diagnostic_notifications)
          else
            print_result(project: project, notifications: diagnostic_notifications)
          end
        else
          stdout.puts Rainbow("Unexpected error reported. 🚨").red.bold
          1
        end
      end

      def build_typecheck_params(project)
        params = { library_paths: [], inline_paths: [], signature_paths: [], code_paths: [] } #: Server::CustomMethods::TypeCheck::params

        if command_line_patterns.empty?
          files = Server::TargetGroupFiles.new(project)
          loader = Services::FileLoader.new(base_dir: project.base_dir)

          project.targets.each do |target|
            target.new_env_loader.each_dir do |_, dir|
              RBS::FileFinder.each_file(dir, skip_hidden: true) do |path|
                files.add_library_path(target, path)
              end
            end

            loader.each_path_in_target(target) do |path|
              files.add_path(path)
            end
          end

          project.targets.each do |target|
            target.groups.each do |group|
              if active_group?(group)
                load_files(files, target, group, params: params)
              end
            end
            if active_group?(target)
              load_files(files, target, target, params: params)
            end
          end
        else
          command_line_patterns.each do |pattern|
            path = Pathname(pattern)
            path = project.absolute_path(path)
            next unless path.file?
            if target = project.target_for_source_path(path)
              params[:code_paths] << [target.name.to_s, path.to_s]
            end
            if target = project.target_for_signature_path(path)
              params[:signature_paths] << [target.name.to_s, path.to_s]
            end
          end
        end

        params
      end

      def wait_for_daemon(timeout: 300)
        stdout.puts "Daemon is warming up, waiting for it to be ready..."
        start_time = Time.now
        dots_printed = 0

        loop do
          if Daemon.running?
            stdout.puts unless dots_printed == 0
            return true
          end

          elapsed = Time.now - start_time
          if elapsed > timeout
            stdout.puts unless dots_printed == 0
            Steep.logger.warn { "Daemon warm-up timed out after #{timeout}s" }
            return false
          end

          unless Daemon.starting?
            stdout.puts unless dots_printed == 0
            Steep.logger.warn { "Daemon process died during warm-up" }
            return false
          end

          sleep 1
          stdout.print "."
          stdout.flush
          dots_printed += 1
        end
      end
    end
  end
end
