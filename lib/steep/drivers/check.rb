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

      include Utils::DriverHelper

      def initialize(stdout:, stderr:)
        @stdout = stdout
        @stderr = stderr
        @command_line_patterns = []
        @severity_level = :warning
        @jobs_option = Utils::JobsOption.new()
      end

      def run
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
        client_writer.write({ method: :initialize, id: initialize_id, params: {} })
        wait_for_response_id(reader: client_reader, id: initialize_id)

        request_guid = SecureRandom.uuid
        Steep.logger.info { "Starting type checking: #{request_guid}" }
        client_writer.write({ method: "$/typecheck", params: { guid: request_guid } })

        diagnostic_notifications = [] #: Array[LanguageServer::Protocol::Interface::PublishDiagnosticsParams]
        error_messages = [] #: Array[String]
        client_reader.read do |response|
          case
          when response[:method] == "textDocument/publishDiagnostics"
            ds = response[:params][:diagnostics]
            ds.select! {|d| keep_diagnostic?(d, severity_level: severity_level) }
            if ds.empty?
              stdout.print "."
            else
              stdout.print "F"
            end
            diagnostic_notifications << response[:params]
            stdout.flush
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

        stdout.puts
        stdout.puts

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
      rescue Errno::EPIPE => error
        stdout.puts Rainbow("Steep shutdown with an error: #{error.inspect}").red.bold
        return 1
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
