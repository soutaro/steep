module Steep
  module Drivers
    class Langserver
      attr_reader :stdout
      attr_reader :stderr
      attr_reader :stdin
      attr_reader :latest_update_version
      attr_reader :write_mutex
      attr_reader :type_check_queue
      attr_reader :type_check_thread

      include Utils::DriverHelper

      TypeCheckRequest = Struct.new(:version, keyword_init: true)

      def initialize(stdout:, stderr:, stdin:)
        @stdout = stdout
        @stderr = stderr
        @stdin = stdin
        @write_mutex = Mutex.new
        @type_check_queue = Queue.new
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

        loader = Project::FileLoader.new(project: project)
        loader.load_sources([])
        loader.load_signatures()

        interaction_worker = Server::WorkerProcess.spawn_worker(:interaction, name: "interaction", steepfile: project.steepfile_path)
        signature_worker = Server::WorkerProcess.spawn_worker(:signature, name: "signature", steepfile: project.steepfile_path)
        code_workers = Server::WorkerProcess.spawn_code_workers(steepfile: project.steepfile_path)

        master = Server::Master.new(
          project: project,
          reader: reader,
          writer: writer,
          interaction_worker: interaction_worker,
          signature_worker: signature_worker,
          code_workers: code_workers
        )

        master.start()

        0
      end
    end
  end
end
