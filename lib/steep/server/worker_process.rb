module Steep
  module Server
    class WorkerProcess
      attr_reader :reader
      attr_reader :writer
      attr_reader :stderr

      attr_reader :type
      attr_reader :name
      attr_reader :wait_thread
      attr_reader :index
      attr_reader :known_versions
      attr_accessor :in_flight

      def initialize(type:, reader:, writer:, stderr:, wait_thread:, name:, index: nil)
        @type = type
        @reader = reader
        @writer = writer
        @stderr = stderr
        @wait_thread = wait_thread
        @name = name
        @index = index
        @known_versions = {}
        @in_flight = 0
        @retiring = false
        @exiting = false
      end

      def retire!
        @retiring = true
      end

      def retiring?
        @retiring
      end

      def exiting!
        @exiting = true
      end

      def exiting?
        @exiting
      end

      def self.start_worker(type, name:, steepfile:, steep_command:, index: nil, patterns: [])
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

        steep_command ||= "steep"
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

        new(type: type, reader: reader, writer: writer, stderr: stderr, wait_thread: thread, name: name, index: index&.[](1))
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
