module Steep
  module Server
    class WorkerProcess
      attr_reader :reader
      attr_reader :writer
      attr_reader :stderr

      attr_reader :name
      attr_reader :wait_thread
      attr_reader :index
      attr_reader :io_socket

      def initialize(reader:, writer:, io_socket: nil, stderr:, wait_thread:, name:, index: nil)
        @reader = reader
        @writer = writer
        @stderr = stderr
        @io_socket = io_socket
        @wait_thread = wait_thread
        @name = name
        @index = index
      end

      def self.start_worker(type, name:, steepfile:, steep_command:, index: nil, delay_shutdown: false, patterns: [])
        if Steep.can_fork? && !steep_command
          fork_worker(
            type,
            name: name,
            steepfile: steepfile,
            index: index,
            is_primary: index && (index[1] == 0 && index[0] >= 2),
            delay_shutdown: delay_shutdown,
            patterns: patterns
          )
        else
          spawn_worker(
            type,
            name: name,
            steepfile: steepfile,
            steep_command: steep_command || "steep",
            index: index,
            delay_shutdown: delay_shutdown,
            patterns: patterns
          )
        end
      end

      def self.fork_worker(type, name:, steepfile:, index:, delay_shutdown:, patterns:, is_primary:)
        stdin_in, stdin_out = IO.pipe
        stdout_in, stdout_out = IO.pipe
        sock_master, sock_worker = UNIXSocket.socketpair if is_primary

        worker = Drivers::Worker.new(stdout: stdout_out, stdin: stdin_in, stderr: STDERR)

        worker.steepfile = steepfile
        worker.worker_type = type
        worker.worker_name = name
        worker.delay_shutdown = delay_shutdown
        if (max, this = index)
          worker.max_index = max
          worker.index = this
        end
        worker.commandline_args = patterns
        worker.io_socket = sock_worker

        pid = fork do
          Process.setpgid(0, 0)
          Steep.ui_logger.level = :fatal
          stdin_out.close
          stdout_in.close
          sock_master&.close
          worker.run()
        end

        pid or raise

        writer = LanguageServer::Protocol::Transport::Io::Writer.new(stdin_out)
        reader = LanguageServer::Protocol::Transport::Io::Reader.new(stdout_in)

        # @type var wait_thread: Thread & _ProcessWaitThread
        wait_thread = _ = Thread.new { Process.waitpid(pid) }
        wait_thread.define_singleton_method(:pid) { pid }

        stdin_in.close
        stdout_out.close
        sock_worker&.close

        new(
          reader: reader,
          writer: writer,
          stderr: STDERR,
          wait_thread: wait_thread,
          name: name,
          index: index&.[](1),
          io_socket: sock_master,
        )
      end

      def self.spawn_worker(type, name:, steepfile:, steep_command:, index:, delay_shutdown:, patterns:)
        args = ["--name=#{name}"]
        args << "--steepfile=#{steepfile}" if steepfile
        args << (%w(debug info warn error fatal unknown)[Steep.logger.level].yield_self {|log_level| "--log-level=#{log_level}" })

        if Steep.log_output.is_a?(String)
          args << "--log-output=#{Steep.log_output}"
        end

        if (max, this = index)
          args << "--max-index=#{max}"
          args << "--index=#{this}"
        end

        if delay_shutdown
          args << "--delay-shutdown"
        end

        command = case type
                  when :interaction
                    [steep_command, "worker", "--interaction", *args, *patterns]
                  when :typecheck
                    [steep_command, "worker", "--typecheck", *args, *patterns]
                  else
                    raise "Unknown type: #{type}"
                  end

        stdin, stdout, thread = if Gem.win_platform?
                                  __skip__ = Open3.popen2(*command, new_pgroup: true)
                                else
                                  __skip__ = Open3.popen2(*command, pgroup: true)
                                end
        stderr = nil

        writer = LanguageServer::Protocol::Transport::Io::Writer.new(stdin)
        reader = LanguageServer::Protocol::Transport::Io::Reader.new(stdout)

        new(reader: reader, writer: writer, stderr: stderr, wait_thread: thread, name: name, index: index&.[](1))
      end

      def self.start_typecheck_workers(steepfile:, args:, steep_command:, count: [Etc.nprocessors - 1, 1].max || raise, delay_shutdown: false)
        count.times.map do |i|
          start_worker(
            :typecheck,
            name: "typecheck@#{i}",
            steepfile: steepfile,
            steep_command: steep_command,
            index: [count, i],
            patterns: args,
            delay_shutdown: delay_shutdown,
          )
        end
      end

      def redirect_to(worker)
        @writer = worker.writer
      end

      def <<(message)
        writer.write(message)
      end

      def read(&block)
        reader.read(&block)
      end

      def kill(force: false)
        Steep.logger.tagged("WorkerProcess#kill@#{name}(#{pid})") do
          begin
            signal = force ? :KILL : :TERM
            Steep.logger.debug("Sending signal SIG#{signal}...")
            Process.kill(signal, pid)
            Steep.logger.debug("Successfully sent the signal.")
          rescue Errno::ESRCH => error
            Steep.logger.debug("Failed #{error.inspect}")
          end
          unless force
            Steep.logger.debug("Waiting for process exit...")
            wait_thread.join()
            Steep.logger.debug("Confirmed process exit.")
          end
        end
      end

      def pid
        wait_thread.pid
      end
    end
  end
end
