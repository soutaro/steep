module Steep
  module Drivers
    class Watch
      attr_reader :dirs
      attr_reader :stdout
      attr_reader :stderr
      attr_reader :queue

      include Utils::DriverHelper
      include Utils::JobsCount

      LSP = LanguageServer::Protocol

      def initialize(stdout:, stderr:)
        @dirs = []
        @stdout = stdout
        @stderr = stderr
        @queue = Thread::Queue.new
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

        typecheck_workers = Server::WorkerProcess.spawn_typecheck_workers(steepfile: project.steepfile_path, args: dirs.map(&:to_s), count: jobs_count)

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
        client_writer.write(method: "$/typecheck", params: { guid: nil })

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
          stdout.puts Rainbow("🔬 Type checking updated files...").bold

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
        end.tap(&:start)

        begin
          stdout.puts Rainbow("👀 Watching directories, Ctrl-C to stop.").bold
          client_reader.read do |response|
            case response[:method]
            when "textDocument/publishDiagnostics"
              uri = URI.parse(response[:params][:uri])
              path = project.relative_path(Pathname(uri.path))
              buffer = RBS::Buffer.new(content: path.read, name: path)
              printer = DiagnosticPrinter.new(stdout: stdout, buffer: buffer)

              diagnostics = response[:params][:diagnostics]

              unless diagnostics.empty?
                diagnostics.each do |diagnostic|
                  printer.print(diagnostic)
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
          shutdown_id = request_id()
          stdout.puts "Shutting down workers..."
          client_writer.write({ method: :shutdown, id: shutdown_id })
          client_writer.write({ method: :exit })
          client_writer.io.close()
        end

        listener.stop
        begin
          main_thread.join
        rescue Interrupt
          master.kill
          main_thread.join
        end

        0
      end
    end
  end
end
