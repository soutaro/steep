module Steep
  module Server
    class WorkerProcess
      attr_reader :reader
      attr_reader :writer
      attr_reader :stderr

      attr_reader :name
      attr_reader :wait_thread
      attr_reader :index

      def initialize(reader:, writer:, stderr:, wait_thread:, name:, index: nil)
        @reader = reader
        @writer = writer
        @stderr = stderr
        @wait_thread = wait_thread
        @name = name
        @index = index
      end

      def self.spawn_worker(type, name:, steepfile:, steep_command: "steep", options: [], delay_shutdown: false, index: nil)
        log_level = %w(debug info warn error fatal unknown)[Steep.logger.level]
        command = case type
                  when :interaction
                    [steep_command, "worker", "--interaction", "--name=#{name}", "--log-level=#{log_level}", "--steepfile=#{steepfile}", *options]
                  when :typecheck
                    [steep_command, "worker", "--typecheck", "--name=#{name}", "--log-level=#{log_level}", "--steepfile=#{steepfile}", *options]
                  else
                    raise "Unknown type: #{type}"
                  end

        if delay_shutdown
          command << "--delay-shutdown"
        end

        stdin, stdout, thread = Open3.popen2(*command, pgroup: true)
        stderr = nil

        writer = LanguageServer::Protocol::Transport::Io::Writer.new(stdin)
        reader = LanguageServer::Protocol::Transport::Io::Reader.new(stdout)

        new(reader: reader, writer: writer, stderr: stderr, wait_thread: thread, name: name, index: index)
      end

      def self.spawn_typecheck_workers(steepfile:, args:, steep_command: "steep", count: [Etc.nprocessors - 1, 1].max, delay_shutdown: false)
        count.times.map do |i|
          spawn_worker(:typecheck,
                       name: "typecheck@#{i}",
                       steepfile: steepfile,
                       steep_command: steep_command,
                       options: ["--max-index=#{count}", "--index=#{i}", *args],
                       delay_shutdown: delay_shutdown,
                       index: i)
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
