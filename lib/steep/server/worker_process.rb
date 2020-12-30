module Steep
  module Server
    class WorkerProcess
      attr_reader :reader
      attr_reader :writer
      attr_reader :stderr

      attr_reader :name
      attr_reader :wait_thread

      def initialize(reader:, writer:, stderr:, wait_thread:, name:)
        @reader = reader
        @writer = writer
        @stderr = stderr
        @wait_thread = wait_thread
        @name = name
      end

      def self.spawn_worker(type, name:, steepfile:, delay_shutdown: false)
        log_level = %w(debug info warn error fatal unknown)[Steep.logger.level]
        command = case type
                  when :code
                    ["steep", "worker", "--code", "--name=#{name}", "--log-level=#{log_level}", "--steepfile=#{steepfile}"]
                  when :signature
                    ["steep", "worker", "--signature", "--name=#{name}", "--log-level=#{log_level}", "--steepfile=#{steepfile}"]
                  when :interaction
                    ["steep", "worker", "--interaction", "--name=#{name}", "--log-level=#{log_level}", "--steepfile=#{steepfile}"]
                  else
                    raise
                  end

        if delay_shutdown
          command << "--delay-shutdown"
        end

        stdin, stdout, thread = Open3.popen2(*command, pgroup: true)
        stderr = nil

        writer = LanguageServer::Protocol::Transport::Io::Writer.new(stdin)
        reader = LanguageServer::Protocol::Transport::Io::Reader.new(stdout)

        new(reader: reader, writer: writer, stderr: stderr, wait_thread: thread, name: name)
      end

      def self.spawn_code_workers(steepfile:, count: [Etc.nprocessors-3, 1].max, delay_shutdown: false)
        count.times.map do |i|
          spawn_worker(:code, name: "code@#{i}", steepfile: steepfile, delay_shutdown: delay_shutdown)
        end
      end

      def <<(message)
        writer.write(message)
      end

      def read(&block)
        reader.read(&block)
      end

      def kill
        Process.kill(:TERM, @wait_thread.pid)
      end
    end
  end
end
