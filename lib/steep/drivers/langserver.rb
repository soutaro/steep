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

      include Utils::DriverHelper

      def initialize(stdout:, stderr:, stdin:)
        @stdout = stdout
        @stderr = stderr
        @stdin = stdin
        @write_mutex = Mutex.new
        @type_check_queue = Queue.new
        @jobs_option = Utils::JobsOption.new(jobs_count_modifier: -1)
        @refork = false
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

        infer_contracts(@project)
        infer_postconditions(@project)

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

        master.start()

        0
      end

      private

      def infer_contracts(project)
        runner = Contracts::Runner.new(project)
        contracts = runner.run
        runner.write(contracts)
        Steep.logger.info do
          if contracts.any?
            "Inferred #{contracts.size} precondition(s); sidecar at #{project.relative_path(runner.output_path)}"
          else
            "Inferred 0 preconditions; sidecar #{runner.output_path.file? ? "kept" : "absent"}"
          end
        end
      rescue => e
        Steep.logger.warn "Precondition inference failed: #{e.class}: #{e.message}"
      end

      def infer_postconditions(project)
        runner = Postconditions::Runner.new(project)
        entries = runner.run
        runner.write(entries)
        Steep.logger.info do
          if entries.any?
            "Inferred #{entries.size} postcondition(s); sidecar at #{project.relative_path(runner.output_path)}"
          else
            "Inferred 0 postconditions; sidecar #{runner.output_path.file? ? "kept" : "absent"}"
          end
        end
      rescue => e
        Steep.logger.warn "Postcondition inference failed: #{e.class}: #{e.message}"
      end
    end
  end
end
