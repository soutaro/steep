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

      include Utils::DriverHelper

      def initialize(stdout:, stderr:, stdin:)
        @stdout = stdout
        @stderr = stderr
        @stdin = stdin
        @write_mutex = Mutex.new
        @type_check_queue = Queue.new
        @jobs_option = Utils::JobsOption.new(jobs_count_modifier: -1)
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
          typecheck_workers: typecheck_workers
        )
        master.typecheck_automatically = true

        master.start()

        0
      end
    end
  end
end
