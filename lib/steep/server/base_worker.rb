module Steep
  module Server
    class BaseWorker
      LSP = LanguageServer::Protocol

      include Utils

      attr_accessor :queue_delay

      attr_reader :project
      attr_reader :reader, :writer

      def initialize(project:, reader:, writer:)
        @project = project
        @reader = reader
        @writer = writer

        self.queue_delay = 0.3
      end

      def handle_request(request)
        # process request
      end

      def handle_job(job)
        # process async job
      end

      def run
        tags = Steep.logger.formatter.current_tags.dup
        thread = Thread.new do
          Steep.logger.formatter.push_tags(*tags)
          Steep.logger.tagged "background" do
            while job = queue.pop
              handle_job(job)
            end
          end
        end

        Steep.logger.tagged "frontend" do
          begin
            reader.read do |request|
              case request[:method]
              when "shutdown"
                # nop
              when "exit"
                break
              else
                handle_request(request)
              end
            end
          ensure
            queue << nil
            thread.join
          end
        end
      end

      def enqueue(object)
        if queue_delay == 0
          Steep.logger.debug { "Queueing immediately: #{object.inspect}..." }
          queue << object
        else
          Steep.logger.debug { "Scheduling enqueue: delay=#{delay}, #{object.inspect}..." }
          Concurrent::ScheduledTask.execute(queue_delay) do
            Steep.logger.debug { "Queueing: #{object.inspect}..." }
            queue << object
          end
        end
      end
    end
  end
end
