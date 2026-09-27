module Steep
  module Drivers
    class Langserver
      attr_reader :stdout
      attr_reader :stderr
      attr_reader :stdin
      attr_reader :write_mutex
      attr_reader :type_check_queue
      attr_reader :type_check_thread
      attr_reader :jobs_option
      attr_accessor :command_socket

      include Utils::DriverHelper

      def initialize(stdout:, stderr:, stdin:)
        @stdout = stdout
        @stderr = stderr
        @stdin = stdin
        @write_mutex = Mutex.new
        @type_check_queue = Queue.new
        @jobs_option = Utils::JobsOption.new(jobs_count_modifier: -1)
        @command_socket = true
      end

      # The reader and the writer work on duplicates of the standard streams, never on the streams themselves.
      #
      # Spawning a worker redirects the standard input and output of the child. Without `fork`, Ruby applies
      # the redirection to the fds 0 and 1 of this process while it spawns the child and restores them
      # afterwards. The `dup2` of the redirection waits for the lock of the fd in the C runtime, which the
      # thread reading the stream holds while it is blocked in a read. The spawn would wait for the client
      # to send something, with the GVL held, and the whole server would stop until then.
      #
      def writer
        @writer ||= LanguageServer::Protocol::Transport::Io::Writer.new(stdout.dup)
      end

      def reader
        @reader ||= LanguageServer::Protocol::Transport::Io::Reader.new(stdin.dup)
      end

      def project
        @project or raise "Empty #project"
      end

      def run
        @project = load_config()

        launcher = Server::SpawnLauncher.new(
          steepfile: project.steepfile_path,
          steep_command: jobs_option.steep_command,
          typecheck_count: jobs_option.jobs_count_value
        )

        master = Server::Master.new(
          project: project,
          reader: reader,
          writer: writer,
          launcher: launcher
        )
        master.typecheck_automatically = true

        socket = start_command_socket(master)

        begin
          master.start()
        ensure
          socket&.stop
        end

        0
      end

      # Starts accepting `steep query`/`steep check` connections on the UNIX socket
      #
      # Returns `nil` when the command socket is disabled, is not supported on the platform,
      # or is already served by another process.
      #
      def start_command_socket(master)
        return nil unless command_socket

        configuration = Daemon::Configuration.new(base_dir: project.base_dir.to_s)
        socket = Server::CommandSocket.new(master: master, configuration: configuration)

        if socket.start
          stderr.puts "Steep command socket is ready: #{configuration.socket_path}"
          socket
        else
          stderr.puts "Steep command socket is not available: #{configuration.socket_path}"
          nil
        end
      rescue NotImplementedError, StandardError => error
        Steep.logger.error { "Failed to start command socket: #{error.inspect}" }
        stderr.puts "Failed to start Steep command socket: #{error.message}"
        nil
      end
    end
  end
end
