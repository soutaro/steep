module Steep
  module Server
    class BaseWorker
      LSP = LanguageServer::Protocol

      attr_reader :project
      attr_reader :reader, :writer, :queue

      ShutdownJob = _ = Struct.new(:id, keyword_init: true)

      def initialize(project:, reader:, writer:)
        @project = project
        @reader = reader
        @writer = writer
        @skip_job = false
        @shutdown = false
        @skip_jobs_after_shutdown = false
      end

      def skip_jobs_after_shutdown!(flag = true)
        @skip_jobs_after_shutdown = flag
      end

      def skip_jobs_after_shutdown?
        @skip_jobs_after_shutdown
      end

      def skip_job?
        @skip_job
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
          Thread.current.abort_on_exception = true

          Steep.logger.formatter.push_tags(*tags)
          Steep.logger.tagged "background" do
            while job = queue.pop
              case job
              when ShutdownJob
                writer.write(id: job.id, result: nil)
              else
                if skip_job?
                  Steep.logger.info "Skipping job..."
                else
                  begin
                    handle_job(job)
                  rescue => exn
                    Steep.log_error exn
                    writer.write(
                      {
                        method: "window/showMessage",
                        params: {
                          type: LSP::Constant::MessageType::ERROR,
                          message: "Unexpected error: #{exn.message} (#{exn.class})"
                        }
                      }
                    )
                  end
                end
              end
            end
          end
        end

        Steep.logger.tagged "frontend" do
          begin
            reader.read do |request|
              Steep.logger.info "Received message from master: #{request[:method]}(#{request[:id]})"
              case request[:method]
              when "shutdown"
                queue << ShutdownJob.new(id: request[:id])
                @skip_job = skip_jobs_after_shutdown?
                queue.close
              when "exit"
                break
              else
                handle_request(request) unless @shutdown
              end
            end
          ensure
            thread.join
          end
        end
      end
    end
  end
end
