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
      attr_accessor :refork
      attr_accessor :command_socket

      include Utils::DriverHelper

      def initialize(stdout:, stderr:, stdin:)
        @stdout = stdout
        @stderr = stderr
        @stdin = stdin
        @write_mutex = Mutex.new
        @type_check_queue = Queue.new
        @jobs_option = Utils::JobsOption.new(jobs_count_modifier: -1)
        @refork = false
        @command_socket = true
      end

      def writer
        @writer ||= LanguageServer::Protocol::Transport::Io::Writer.new(stdout)
      end

      def reader
        @reader ||= LanguageServer::Protocol::Transport::Io::Reader.new(stdin)
      end

      def project
        @project or raise "Empty #project"
      end

      def run
        @project = load_config()

        interaction_worker = Server::WorkerProcess.start_worker(:interaction, name: "interaction", steepfile: project.steepfile_path, steep_command: jobs_option.steep_command)
        typecheck_workers = Server::WorkerProcess.start_typecheck_workers(steepfile: project.steepfile_path, args: [], steep_command: jobs_option.steep_command, count: jobs_option.jobs_count_value)

        master = Server::Master.new(
          project: project,
          reader: reader,
          writer: writer,
          interaction_worker: interaction_worker,
          typecheck_workers: typecheck_workers,
          refork: refork,
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

        configuration = Daemon::Configuration.new(base_dir: project.steepfile_path.parent.to_s)
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
