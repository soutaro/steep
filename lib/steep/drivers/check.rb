module Steep
  module Drivers
    class Check
      attr_reader :stdout
      attr_reader :stderr
      attr_reader :command_line_patterns

      include Utils::DriverHelper

      def initialize(stdout:, stderr:)
        @stdout = stdout
        @stderr = stderr
        @command_line_patterns = []

        self.dump_all_types = false
      end

      def run
        project = load_config()

        loader = Project::FileLoader.new(project: project)
        loader.load_sources(command_line_patterns)
        loader.load_signatures()

        stdout.puts "# Type checking files:"
        stdout.puts

        client_read, server_write = IO.pipe
        server_read, client_write = IO.pipe

        client_reader = LanguageServer::Protocol::Transport::Io::Reader.new(client_read)
        client_writer = LanguageServer::Protocol::Transport::Io::Writer.new(client_write)

        server_reader = LanguageServer::Protocol::Transport::Io::Reader.new(server_read)
        server_writer = LanguageServer::Protocol::Transport::Io::Writer.new(server_write)

        interaction_worker = Server::WorkerProcess.spawn_worker(:interaction, name: "interaction", steepfile: project.steepfile_path, delay_shutdown: true)
        signature_worker = Server::WorkerProcess.spawn_worker(:signature, name: "signature", steepfile: project.steepfile_path, delay_shutdown: true)
        code_workers = Server::WorkerProcess.spawn_code_workers(steepfile: project.steepfile_path, delay_shutdown: true)

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

        client_writer.write({ method: :initialize, id: 0 })

        shutdown_id = -1
        client_writer.write({ method: :shutdown, id: shutdown_id })

        responses = []
        client_reader.read do |response|
          case
          when response[:method] == "textDocument/publishDiagnostics"
            ds = response[:params][:diagnostics]
            if ds.empty?
              stdout.print "."
            else
              stdout.print "F"
            end
            responses << response[:params]
            stdout.flush
          when response[:id] == shutdown_id
            break
          end
        end

        client_writer.write({ method: :exit })
        client_writer.io.close()

        main_thread.join()

        stdout.puts
        stdout.puts

        if responses.all? {|res| res[:diagnostics].empty? }
          stdout.puts Rainbow("No type error detected").green
          0
        else
          errors = responses.reject {|res| res[:diagnostics].empty? }
          total = errors.sum {|res| res[:diagnostics].size }
          stdout.puts Rainbow("Detected #{total} problems on #{errors.size} files").red
          stdout.puts

          errors.each do |resp|
            path = project.relative_path(Pathname(URI.parse(resp[:uri]).path))
            buffer = RBS::Buffer.new(name: path, content: path.read)
            resp[:diagnostics].each do |diag|
              severity = [nil, Rainbow("error").red, Rainbow("warning").yellow, Rainbow("info").blue][diag[:severity]]
              if severity
                start = diag[:range][:start]
                loc = Rainbow("#{path}:#{start[:line]+1}:#{start[:character]}").magenta
                head, *rest = diag[:message].split(/\n/)
                head = Rainbow(head).underline
                stdout.puts "#{loc}: [#{severity}] #{head}"
                rest.each do |line|
                  stdout.puts "  #{line}"
                end
                stdout.puts

                source_line = buffer.lines[start[:line]] || ""
                if diag[:range][:start][:line] == diag[:range][:end][:line]
                  before = source_line[0...diag[:range][:start][:character]]
                  subject = source_line[diag[:range][:start][:character]...diag[:range][:end][:character]]
                  after = source_line[diag[:range][:end][:character]...]
                  puts "  | #{before}#{Rainbow(subject).red}#{after}"
                else
                  before = source_line[0...diag[:range][:start][:character]]
                  subject = source_line[diag[:range][:start][:character]...]
                  puts "  | #{before}#{Rainbow(subject).red}"
                end


                stdout.puts
              end
            end
          end
          1
        end
      end
    end
  end
end
