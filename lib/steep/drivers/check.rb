module Steep
  module Drivers
    class Check
      LSP = LanguageServer::Protocol

      attr_reader :stdout
      attr_reader :stderr
      attr_reader :command_line_patterns

      include Utils::DriverHelper

      def initialize(stdout:, stderr:)
        @stdout = stdout
        @stderr = stderr
        @command_line_patterns = []
      end

      def run
        project = load_config()

        loader = Project::FileLoader.new(project: project)
        loader.load_sources(command_line_patterns)
        loader.load_signatures()

        stdout.puts Rainbow("# Type checking files:").bold
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
        error_messages = []
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
          when response[:method] == "window/showMessage"
            # Assuming ERROR message means unrecoverable error.
            message = response[:params]
            if message[:type] == LSP::Constant::MessageType::ERROR
              error_messages << message[:message]
            end
          when response[:id] == shutdown_id
            break
          end
        end

        client_writer.write({ method: :exit })
        client_writer.io.close()

        main_thread.join()

        stdout.puts
        stdout.puts

        case
        when responses.all? {|res| res[:diagnostics].empty? } && error_messages.empty?
          emoji = %w(🫖 🫖 🫖 🫖 🫖 🫖 🫖 🫖 🍵 🧋 🧉).sample
          stdout.puts Rainbow("No type error detected. #{emoji}").green.bold
          0
        when !error_messages.empty?
          stdout.puts Rainbow("Unexpected error reported. 🚨").red.bold
          1
        else
          errors = responses.reject {|res| res[:diagnostics].empty? }
          total = errors.sum {|res| res[:diagnostics].size }
          stdout.puts Rainbow("Detected #{total} problems from #{errors.size} files").red.bold
          stdout.puts

          errors.each do |resp|
            path = project.relative_path(Pathname(URI.parse(resp[:uri]).path))
            buffer = RBS::Buffer.new(name: path, content: path.read)
            printer = DiagnosticPrinter.new(buffer: buffer, stdout: stdout)

            resp[:diagnostics].each do |diag|
              printer.print(diag)
              stdout.puts
            end
          end
          1
        end
      end
    end
  end
end
