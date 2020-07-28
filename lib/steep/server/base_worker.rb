module Steep
  module Server
    class BaseWorker
      LSP = LanguageServer::Protocol

      include Utils

      attr_reader :project
      attr_reader :reader, :writer

      def initialize(project:, reader:, writer:)
        @project = project
        @reader = reader
        @writer = writer
        @shutdown = false
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
              handle_job(job) unless @shutdown
            end
          end
        end

        Steep.logger.tagged "frontend" do
          begin
            reader.read do |request|
              case request[:method]
              when "shutdown"
                @shutdown = true
              when "exit"
                break
              else
                handle_request(request) unless @shutdown
              end
            end
          ensure
            queue << nil
            thread.join
          end
        end
      end
    end
  end
end
