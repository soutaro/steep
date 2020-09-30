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

      def self.spawn_worker(type, name:, steepfile:)
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

        stdin, stdout, thread = Open3.popen2(*command, pgroup: true)
        stderr = nil

        writer = LanguageServer::Protocol::Transport::Io::Writer.new(stdin)
        reader = LanguageServer::Protocol::Transport::Io::Reader.new(stdout)

        new(reader: reader, writer: writer, stderr: stderr, wait_thread: thread, name: name)
      end

      def self.spawn_code_workers(steepfile:, count: [Etc.nprocessors-3, 1].max)
        count.times.map do |i|
          spawn_worker(:code, name: "code@#{i}", steepfile: steepfile)
        end
      end

      def <<(message)
        writer.write(message)
      end

      def read(&block)
        reader.read(&block)
      end

      def shutdown
        self << { method: :shutdown, params: nil }
        self << { method: :exit, params: nil }

        writer.io.close()
        @wait_thread.join()
      end
    end
  end
end
