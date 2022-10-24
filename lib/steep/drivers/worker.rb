module Steep
  module Drivers
    class Worker
      attr_reader :stdout, :stderr, :stdin

      attr_accessor :worker_type
      attr_accessor :worker_name
      attr_accessor :delay_shutdown
      attr_accessor :max_index
      attr_accessor :index
      attr_accessor :commandline_args

      include Utils::DriverHelper

      def initialize(stdout:, stderr:, stdin:)
        @stdout = stdout
        @stderr = stderr
        @stdin = stdin
        @commandline_args = []
      end

      def run()
        Steep.logger.tagged("#{worker_type}:#{worker_name}") do
          project = load_config()

          reader = LanguageServer::Protocol::Transport::Io::Reader.new(stdin)
          writer = LanguageServer::Protocol::Transport::Io::Writer.new(stdout)

          worker = case worker_type
                   when :typecheck
                     assignment = Services::PathAssignment.new(max_index: max_index, index: index)
                     Server::TypeCheckWorker.new(project: project,
                                                 reader: reader,
                                                 writer: writer,
                                                 assignment: assignment,
                                                 commandline_args: commandline_args)
                   when :interaction
                     Server::InteractionWorker.new(project: project, reader: reader, writer: writer)
                   else
                     raise "Unknown worker type: #{worker_type}"
                   end

          unless delay_shutdown
            worker.skip_jobs_after_shutdown!
          end

          Steep.logger.info "Starting #{worker_type} worker..."

          worker.run()
        rescue Interrupt
          Steep.logger.info "Shutting down by interrupt..."
        end

        0
      end
    end
  end
end
