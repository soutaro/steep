module Steep
  module Drivers
    class Watch
      attr_reader :dirs
      attr_reader :stdout
      attr_reader :stderr
      attr_reader :queue

      include Utils::DriverHelper

      def initialize(stdout:, stderr:)
        @dirs = []
        @stdout = stdout
        @stderr = stderr
        @queue = Thread::Queue.new
      end

      def run()
        if dirs.empty?
          stdout.puts "Specify directories to watch"
          return 1
        end

        project = load_config()

        loader = Project::FileLoader.new(project: project)
        loader.load_sources(dirs)
        loader.load_signatures()

        client_read, server_write = IO.pipe
        server_read, client_write = IO.pipe

        client_reader = LanguageServer::Protocol::Transport::Io::Reader.new(client_read)
        client_writer = LanguageServer::Protocol::Transport::Io::Writer.new(client_write)

        server_reader = LanguageServer::Protocol::Transport::Io::Reader.new(server_read)
        server_writer = LanguageServer::Protocol::Transport::Io::Writer.new(server_write)

        interaction_worker = Server::WorkerProcess.spawn_worker(:interaction, name: "interaction", steepfile: project.steepfile_path)
        signature_worker = Server::WorkerProcess.spawn_worker(:signature, name: "signature", steepfile: project.steepfile_path)
        code_workers = Server::WorkerProcess.spawn_code_workers(steepfile: project.steepfile_path)

        master = Server::Master.new(
          project: project,
          reader: server_reader,
          writer: server_writer,
          interaction_worker: interaction_worker,
          signature_worker: signature_worker,
          code_workers: code_workers
        )

        main_thread = Thread.start do
          master.start()
        end
        main_thread.abort_on_exception = true

        client_writer.write(method: "initialize", id: 0)

        Steep.logger.info "Watching #{dirs.join(", ")}..."
        listener = Listen.to(*dirs.map(&:to_s)) do |modified, added, removed|
          stdout.puts "🔬 Type checking updated files..."

          version = Time.now.to_i
          Steep.logger.tagged "watch" do
            Steep.logger.info "Received file system updates: modified=[#{modified.join(",")}], added=[#{added.join(",")}], removed=[#{removed.join(",")}]"

            (modified + added).each do |path|
              client_writer.write(
                method: "textDocument/didChange",
                params: {
                  textDocument: {
                    uri: "file://#{path}",
                    version: version
                  },
                  contentChanges: [
                    {
                      text: Pathname(path).read
                    }
                  ]
                }
              )
            end

            removed.each do |path|
              client_writer.write(
                method: "textDocument/didChange",
                params: {
                  textDocument: {
                    uri: "file://#{path}",
                    version: version
                  },
                  contentChanges: [
                    {
                      text: ""
                    }
                  ]
                }
              )
            end
          end
        end.tap(&:start)

        begin
          stdout.puts "👀 Watching directories, Ctrl-C to stop."
          client_reader.read do |response|
            case response[:method]
            when "textDocument/publishDiagnostics"
              uri = URI.parse(response[:params][:uri])
              path = project.relative_path(Pathname(uri.path))

              diagnostics = response[:params][:diagnostics]

              unless diagnostics.empty?
                diagnostics.each do |diagnostic|
                  start = diagnostic[:range][:start]
                  loc = "#{start[:line]+1}:#{start[:character]}"
                  message = diagnostic[:message].chomp.lines.join("  ")

                  stdout.puts "#{path}:#{loc}: #{message}"
                end
              end
            end
          end
        rescue Interrupt
          stdout.puts "Shutting down workers..."
          client_writer.write({ method: :shutdown, id: 10000 })
          client_writer.write({ method: :exit })
          client_writer.io.close()
        end

        listener.stop
        main_thread.join

        0
      end
    end
  end
end
