module Steep
  module Drivers
    class Watch
      attr_reader :dirs
      attr_reader :stdout
      attr_reader :stderr
      attr_reader :queue
      attr_accessor :severity_level

      include Utils::DriverHelper
      include Utils::JobsCount

      LSP = LanguageServer::Protocol

      class Session
        attr_reader :guid
        attr_reader :changed_paths
        attr_reader :diagnostics
        attr_reader :files
        attr_reader :started_at

        def initialize(guid:, changed_paths:, files:, started_at: Time.now)
          @started_at = started_at
          @guid = guid
          @changed_paths = changed_paths
          @diagnostics = {}
          @files = files
        end

        def focus_diagnostics
          if changed_paths
            hash = {}

            changed_paths.each do |path|
              hash[path] = diagnostics[path] || []
            end

            hash
          end
        end

        def summary_diagnostics
          diagnostics.except(*changed_paths)
        end

        def error_diagnostics
          diagnostics.select {|path, diagnostics| diagnostics.size > 0 }
        end

        def duration(now = Time.now)
          (now - started_at).to_f.ceil(2)
        end
      end

      StartEvent = Struct.new(:files, keyword_init: true)
      ListenEvent = Struct.new(:changes, keyword_init: true)
      LSPEvent = Struct.new(:message, keyword_init: true) do
        def method
          message[:method]
        end

        def params
          message[:params]
        end
      end

      class EventLoop
        include Utils::DriverHelper

        attr_reader :stdout, :queue, :client_writer, :project
        attr_reader :current_session, :last_session
        attr_reader :severity_level

        def initialize(stdout:, queue:, client_writer:, project:, severity_level:)
          @stdout = stdout
          @queue = queue
          @client_writer = client_writer
          @project = project
          @severity_level = severity_level
        end

        def start
          while event = queue.pop
            handle_event(event)
          end
        end

        def handle_event(event)
          case event
          when StartEvent
            start_type_checking(changed_paths: nil, files: event.files)

          when ListenEvent
            version = (Time.now.to_f * 1000).to_i

            event.changes.each do |path, content|
              client_writer.write(
                method: "textDocument/didChange",
                params: {
                  textDocument: { uri: "file://#{project.absolute_path(path)}", version: version },
                  contentChanges: [{ text: content }]
                }
              )
            end

            latest_session = (current_session || last_session) or raise

            start_type_checking(
              changed_paths: Set.new(event.changes.keys),
              files: latest_session.files.merge(event.changes)
            )

          when LSPEvent
            case event.method
            when "$/progress"
              if event.params[:value][:kind] == "end"
                type_check_completed(event.params[:token])
              end
            when "textDocument/publishDiagnostics"
              uri = URI.parse(event.params[:uri])
              path = project.relative_path(Pathname(uri.path))
              diagnostics = event.params[:diagnostics]

              diagnostics.filter! {|d| keep_diagnostic?(d) }

              type_check_progress(path, diagnostics)
            when "window/showMessage"
              # Assuming ERROR message means unrecoverable error.
              message = event.params
              if message[:type] == LSP::Constant::MessageType::ERROR
                stdout.puts "Unexpected error reported... 🚨"
              end
            end
          end
        end

        def start_type_checking(changed_paths:, files:)
          guid = SecureRandom.alphanumeric(10)

          if current_session
            stdout.puts
            stdout.puts
            stdout.puts ">> Cancelled 👋"
            stdout.puts
            stdout.flush

            if changed_paths && current_session.changed_paths
              changed_paths = changed_paths + current_session.changed_paths
            end
          end

          @current_session = Session.new(guid: guid, changed_paths: changed_paths, files: files)

          client_writer.write(method: "$/typecheck", params: { guid: guid })

          stdout.puts Rainbow("# Type checking files:").bold
          stdout.puts
        end

        def type_check_completed(guid)
          if current_session&.guid == guid
            stdout.puts
            stdout.puts

            if current_session.changed_paths && last_session
              print_compact_result(current_session, last_session)
            else
              print_detail_result(current_session)
            end

            stdout.puts Rainbow(">> Type check completed in #{current_session.duration}secs").bold
            stdout.puts
            stdout.flush

            @last_session = current_session
            @current_session = nil
          end
        end

        def print_compact_result(current, last)
          unless (focus = current.focus_diagnostics).empty?
            nonempties = {}
            empties = {}

            focus.each do |path, diagnostics|
              if diagnostics.empty?
                empties[path] = diagnostics
              else
                nonempties[path] = diagnostics
              end
            end

            unless nonempties.empty?
              nonempties.each do |path, diagnostics|
                content = current.files[path] || raise
                buffer = RBS::Buffer.new(content: content, name: path)
                printer = DiagnosticPrinter.new(stdout: stdout, buffer: buffer)

                diagnostics.each do |diagnostic|
                  printer.print(diagnostic)
                  stdout.puts
                end
              end
            end

            unless empties.empty?
              empties.each do |path, _|
                stdout.puts "✅ No type error detected on #{path}"
              end
              stdout.puts
            end
          end

          unless (nonfocus = current.summary_diagnostics).empty?
            unless nonfocus.values.all?(:empty?)
              nonfocus.each do |path, diagnostics|
                last_diagnostics = last.diagnostics[path] || []

                number = Rainbow("%3d" % diagnostics.size)
                diff = Rainbow("%+3d" % (diagnostics.size - last_diagnostics.size))

                if diagnostics.empty?
                  if last_diagnostics.empty?
                    # Nothing changed, no error reported => skip printing summary
                    next
                  else
                    number = number.green
                    diff = diff.green
                  end
                else
                  number = number.red
                  case
                  when last_diagnostics.size > diagnostics.size
                    diff = diff.green
                  when last_diagnostics.size < diagnostics.size
                    diff = diff.red
                  end
                end

                stdout.puts "#{number} errors (#{diff}) on #{path}"
              end

              stdout.puts
            end
          end

          current_errors = current.error_diagnostics
          last_errors = last.error_diagnostics

          current_total = current_errors.each_value.sum(&:size)
          last_total = last_errors.each_value.sum(&:size)

          if current_total == 0 && last_total == 0
            stdout.puts "No error detected"
          else
            error_diff = current_total - last_total
            file_diff = current_errors.size - last_errors.size

            error_message =
              case
              when error_diff > 0
                Rainbow("%+d" % error_diff).red
              when error_diff < 0
                Rainbow("%+d" % error_diff).green
              else
                "+0"
              end
            file_message =
              case
              when file_diff > 0
                Rainbow("%+d" % file_diff).red
              when file_diff < 0
                Rainbow("%+d" % file_diff).green
              else
                "+0"
              end

            stdout.puts Rainbow("#{current_total} (#{error_message}) errors detected from #{current_errors.size} (#{file_message}) files").underline
            stdout.puts
          end
        end

        def print_detail_result(current)
          current.diagnostics.each do |path, diagnostics|
            unless diagnostics.empty?
              content = current.files[path] || raise
              buffer = RBS::Buffer.new(content: content, name: path)
              printer = DiagnosticPrinter.new(stdout: stdout, buffer: buffer)

              diagnostics.each do |diagnostic|
                printer.print(diagnostic)
                stdout.puts
              end
            end
          end

          errors = current.error_diagnostics
          total = errors.each_value.sum(&:size)

          if total == 0
            stdout.puts "No error detected"
          else
            stdout.puts Rainbow("#{total} errors detected from #{errors.size} files").underline
          end
          stdout.puts
        end

        def type_check_progress(path, diagnostics)
          if current_session
            current_session.diagnostics[path] = diagnostics

            if diagnostics.empty?
              stdout.print "."
            else
              stdout.print "F"
            end
            stdout.flush
          end
        end
      end

      attr_reader :current_session
      attr_reader :last_session

      def initialize(stdout:, stderr:)
        @dirs = []
        @stdout = stdout
        @stderr = stderr
        @queue = Thread::Queue.new
        @severity_level = :warning
      end

      def watching?(changed_path, files:, dirs:)
        files.empty? || files.include?(changed_path) || dirs.intersect?(changed_path.ascend.to_set)
      end

      def run()
        if dirs.empty?
          stdout.puts "Specify directories to watch"
          return 1
        end

        project = load_config()

        client_read, server_write = IO.pipe
        server_read, client_write = IO.pipe

        client_reader = LanguageServer::Protocol::Transport::Io::Reader.new(client_read)
        client_writer = LanguageServer::Protocol::Transport::Io::Writer.new(client_write)

        server_reader = LanguageServer::Protocol::Transport::Io::Reader.new(server_read)
        server_writer = LanguageServer::Protocol::Transport::Io::Writer.new(server_write)

        typecheck_workers = Server::WorkerProcess.spawn_typecheck_workers(steepfile: project.steepfile_path, args: dirs.map(&:to_s), steep_command: steep_command, count: jobs_count)

        master = Server::Master.new(
          project: project,
          reader: server_reader,
          writer: server_writer,
          interaction_worker: nil,
          typecheck_workers: typecheck_workers
        )
        master.typecheck_automatically = false
        master.commandline_args.push(*dirs)

        main_thread = Thread.start do
          master.start()
        end
        main_thread.abort_on_exception = true

        initialize_id = request_id()
        client_writer.write(method: "initialize", id: initialize_id)
        wait_for_response_id(reader: client_reader, id: initialize_id)

        stdout.puts Rainbow("👀 Watching directories, Ctrl-C to stop.").bold
        stdout.puts

        Steep.logger.info "Watching #{dirs.join(", ")}..."

        watch_paths = dirs.map do |dir|
          case
          when dir.directory?
            dir.realpath
          when dir.file?
            dir.parent.realpath
          else
            dir
          end
        end

        queue = Queue.new()

        dir_paths = Set.new(dirs.select(&:directory?).map(&:realpath))
        file_paths = Set.new(dirs.select(&:file?).map(&:realpath))

        listener = Listen.to(*watch_paths.map(&:to_s)) do |modified, added, removed|
          version = Time.now.to_i

          Steep.logger.tagged "watch" do
            Steep.logger.info "Received file system updates: modified=[#{modified.join(",")}], added=[#{added.join(",")}], removed=[#{removed.join(",")}]"

            changes = {}

            (modified + added + removed).each do |path|
              path = Pathname(path)

              if watching?(path, files: file_paths, dirs: dir_paths)
                relative_path = project.relative_path(path)

                if path.file?
                  changes[relative_path] = path.read
                else
                  changes[relative_path] = ""
                end
              end
            end

            unless changes.empty?
              queue << ListenEvent.new(changes: changes)
            end
          end
        end.tap(&:start)

        loader = Services::FileLoader.new(base_dir: project.base_dir)
        files = project.targets.each.with_object({}) do |target, files|
          loader.each_path_in_patterns(target.source_pattern) do |path|
            files[path] = project.absolute_path(path).read
          end

          loader.each_path_in_patterns(target.signature_pattern) do |path|
            files[path] = project.absolute_path(path).read
          end
        end
        queue << StartEvent.new(files: files)

        loop_thread = Thread.new do
          EventLoop.new(stdout: stdout, queue: queue, client_writer: client_writer, project: project, severity_level: severity_level).start
        end

        begin
          client_reader.read do |response|
            event = LSPEvent.new(message: response)
            queue << event
          end
        rescue Interrupt
          stdout.puts "Shutting down workers..."
          queue.close
          shutdown_exit(reader: client_reader, writer: client_writer)
        end

        begin
          listener.stop
          loop_thread.join
          main_thread.join
        rescue Interrupt
          master.kill
          loop_thread.kill
          main_thread.join
        end

        0
      end
    end
  end
end
