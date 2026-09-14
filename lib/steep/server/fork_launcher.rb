module Steep
  module Server
    class ForkLauncher
      attr_reader :typecheck_count
      attr_reader :interaction
      attr_reader :patterns
      attr_reader :master
      attr_reader :generation

      def initialize(typecheck_count:, interaction:, patterns: [])
        @typecheck_count = typecheck_count
        @interaction = interaction
        @patterns = patterns
        @master = nil
        @generation = 0
      end

      def start(master)
        # The first generation is forked once the environment thread has loaded the environment
        @master = master
      end

      def stop
      end

      def environment_changing(master, signature_changed:)
        if signature_changed
          # The typecheck workers have the old environment: the jobs wait for the next generation
          master.retire_typecheck_workers
        end
      end

      def environment_updated(master, signature_changed:, versions:)
        # The first generation waits for the environment to be loaded, the next ones for the environment to change
        return unless generation == 0 || signature_changed

        @generation += 1
        Steep.logger.tagged("ForkLauncher(generation=#{generation})") do
          fork_generation(master, versions)
        end
      end

      def fork_generation(master, versions)
        if Process.respond_to?(:warmup)
          Steep.measure("Process.warmup before forking the workers", level: :info) do
            Process.warmup
          end
        end

        workers = [] #: Array[WorkerProcess]

        if interaction
          workers << fork_worker(master, :interaction, name: "interaction@#{generation}", index: nil, versions: versions)
        end

        typecheck_count.times do |i|
          workers << fork_worker(master, :typecheck, name: "typecheck@#{i}.#{generation}", index: [typecheck_count, i], versions: versions)
        end

        begin
          master.job_queue << -> do
            # The previous generation, if any is still working, has the older environment
            master.retire_typecheck_workers
            master.attach_workers(workers)
          end
        rescue ClosedQueueError
          # The server is exiting, and the workers are of no use
          workers.each do |worker|
            worker.kill(force: true)
          end
        end
      end

      def fork_worker(master, type, name:, index:, versions:)
        project = master.project
        service = master.controller.type_check_service or raise "The environment is not loaded yet"

        parent_socket, child_socket = UNIXSocket.pair

        pid = fork do
          run_worker(type, name: name, index: index, project: project, service: service, socket: child_socket)
        end
        pid or raise "fork returned nil in the parent"

        child_socket.close

        # @type var wait_thread: Thread & WorkerProcess::_ProcessWaitThread
        wait_thread = _ = Thread.new { Process.waitpid(pid) }
        wait_thread.define_singleton_method(:pid) { pid }

        Steep.logger.info { "Forked #{type} worker: name=#{name}, pid=#{pid}" }

        worker = WorkerProcess.new(
          type: type,
          reader: LanguageServer::Protocol::Transport::Io::Reader.new(parent_socket),
          writer: LanguageServer::Protocol::Transport::Io::Writer.new(parent_socket),
          stderr: nil,
          wait_thread: wait_thread,
          name: name,
          index: index&.[](1)
        )
        worker.known_versions.merge!(versions)
        worker
      end

      def run_worker(type, name:, index:, project:, service:, socket:)
        Process.setpgid(0, 0)

        # The child inherits every IO of the master: the pipes to the client, the sockets of the other workers, the
        # command socket. Close them, or they would stay open after the master exits.
        ObjectSpace.each_object(IO) do |io|
          next if io.equal?(socket) || io.equal?(STDIN) || io.equal?(STDOUT) || io.equal?(STDERR)
          io.close unless io.closed?
        rescue IOError, SystemCallError
          # Already closed, or not ours to close
        end
        STDIN.reopen(File::NULL)
        STDOUT.reopen(File::NULL, "w")

        # The loggers of the master belong to its threads, which do not exist in the child
        Steep.log_output = Steep.log_output
        Steep.ui_logger.level = :fatal

        reader = LanguageServer::Protocol::Transport::Io::Reader.new(socket)
        writer = LanguageServer::Protocol::Transport::Io::Writer.new(socket)

        worker =
          case type
          when :typecheck
            pair = index or raise "A typecheck worker needs its index"
            max_index, this_index = pair
            TypeCheckWorker.new(
              project: project,
              reader: reader,
              writer: writer,
              assignment: Services::PathAssignment.new(max_index: max_index, index: this_index),
              commandline_args: patterns,
              service: service
            )
          when :interaction
            InteractionWorker.new(project: project, reader: reader, writer: writer, service: service)
          else
            raise "Unknown type: #{type}"
          end

        Steep.logger.tagged("#{type}:#{name}") do
          Steep.logger.info { "Starting #{type} worker forked from the master..." }
          worker.run()
        end

        exit!(0)
      rescue Exception => exn
        begin
          Steep.log_error(exn)
        rescue Exception
          # Nothing else to do
        end
        exit!(1)
      end
    end
  end
end
