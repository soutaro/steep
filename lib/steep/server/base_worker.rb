module Steep
  module Server
    class BaseWorker
      LSP = LanguageServer::Protocol

      attr_reader :project
      attr_reader :reader, :writer, :queue

      def initialize(project:, reader:, writer:)
        @project = project
        @reader = reader
        @writer = writer
        @skip_job = false
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
        tags = Steep.logger.current_tags.dup
        thread = Thread.new do
          Thread.current.abort_on_exception = true

          Steep.logger.push_tags(*tags)
          Steep.logger.tagged "background" do
            while job = queue.pop
              if skip_job?
                Steep.logger.info "Skipping job..."
              else
                begin
                  handle_job(job)
                rescue => exn
                  Steep.log_error exn

                  # Jobs that carry an `id` answer a request. Reply with an error response, or the
                  # client would wait for a response that never arrives.
                  if job.respond_to?(:id) && (id = job.id)
                    writer.write(
                      {
                        id: id,
                        error: {
                          code: LSP::Constant::ErrorCodes::INTERNAL_ERROR,
                          message: "Unexpected error: #{exn.message} (#{exn.class})"
                        }
                      }
                    )
                  end

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

        Steep.logger.tagged "frontend" do
          begin
            reader.read do |request|
              Steep.logger.info "Received message from master: #{request[:method]}(#{request[:id]})"
              case request[:method]
              when "exit"
                break
              else
                handle_request(request)
              end
            end
          ensure
            # Finish the running job and skip the queued ones, on `exit` or when the master is gone
            @skip_job = true
            queue.close
            thread.join
          end
        end
      end
    end
  end
end
