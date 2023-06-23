module Steep
  module Drivers
    class Watch
      attr_reader :dirs
      attr_reader :stdout
      attr_reader :stderr
      attr_reader :queue
      attr_accessor :severity_level
      attr_reader :jobs_option

      include Utils::DriverHelper

      LSP = LanguageServer::Protocol

      def initialize(stdout:, stderr:)
        @dirs = []
        @stdout = stdout
        @stderr = stderr
        @queue = Thread::Queue.new
        @severity_level = :warning
        @jobs_option = Utils::JobsOption.new()
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

        typecheck_workers = Server::WorkerProcess.start_typecheck_workers(steepfile: project.steepfile_path, args: dirs.map(&:to_s), steep_command: jobs_option.steep_command, count: jobs_option.jobs_count_value)

        master = Server::Master.new(
          project: project,
          reader: server_reader,
          writer: server_writer,
          interaction_worker: nil,
          typecheck_workers: typecheck_workers
        )
        master.typecheck_automatically = false
        master.commandline_args.push(*dirs.map(&:to_s))

        main_thread = Thread.start do
          master.start()
        end

        initialize_id = request_id()
        client_writer.write(method: "initialize", id: initialize_id)
        wait_for_response_id(reader: client_reader, id: initialize_id)

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

        dir_paths = Set.new(dirs.select(&:directory?).map(&:realpath))
        file_paths = Set.new(dirs.select(&:file?).map(&:realpath))

        listener = Listen.to(*watch_paths.map(&:to_s)) do |modified, added, removed|
          stdout.print Rainbow("🔬 Type checking updated files...").bold

          version = Time.now.to_i
          Steep.logger.tagged "watch" do
            Steep.logger.info "Received file system updates: modified=[#{modified.join(",")}], added=[#{added.join(",")}], removed=[#{removed.join(",")}]"

            (modified + added).each do |path|
              p = Pathname(path)
              if watching?(p, files: file_paths, dirs: dir_paths)
                client_writer.write(
                  method: "textDocument/didChange",
                  params: {
                    textDocument: { uri: "file://#{path}", version: version },
                    contentChanges: [{ text: p.read }]
                  }
                )
              end
            end

            removed.each do |path|
              p = Pathname(path)
              if watching?(p, files: file_paths, dirs: dir_paths)
                client_writer.write(
                  method: "textDocument/didChange",
                  params: {
                    textDocument: { uri: "file://#{path}", version: version },
                    contentChanges: [{ text: "" }]
                  }
                )
              end
            end
          end

          client_writer.write(method: "$/typecheck", params: { guid: nil })

          stdout.puts Rainbow("done!").bold
        end.tap(&:start)

        begin
          stdout.puts Rainbow("👀 Watching directories, Ctrl-C to stop.").bold

          client_writer.write(method: "$/typecheck", params: { guid: nil })

          client_reader.read do |response|
            case response[:method]
            when "textDocument/publishDiagnostics"
              path = PathHelper.to_pathname(response[:params][:uri]) or break
              buffer = RBS::Buffer.new(content: path.read, name: path)
              printer = DiagnosticPrinter.new(stdout: stdout, buffer: buffer)

              diagnostics = response[:params][:diagnostics]
              diagnostics.filter! {|d| keep_diagnostic?(d, severity_level: severity_level) }

              unless diagnostics.empty?
                diagnostics.each do |diagnostic|
                  printer.print(diagnostic)
                  stdout.flush
                end
              end
            when "window/showMessage"
              # Assuming ERROR message means unrecoverable error.
              message = response[:params]
              if message[:type] == LSP::Constant::MessageType::ERROR
                stdout.puts "Unexpected error reported... 🚨"
              end
            end
          end
        rescue Interrupt
          stdout.puts "Shutting down workers..."
          shutdown_exit(reader: client_reader, writer: client_writer)
        end

        listener.stop
        begin
          main_thread.join
        rescue Interrupt
          master.kill
          begin
            main_thread.join
          rescue
            master.each_worker do |worker|
              worker.kill(force: true)
            end
          end
        end

        0
      end
    end
  end
end
