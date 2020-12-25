module Steep
  module Server
    class Master
      LSP = LanguageServer::Protocol

      attr_reader :steepfile
      attr_reader :project
      attr_reader :reader, :writer
      attr_reader :worker_count
      attr_reader :worker_to_paths

      attr_reader :interaction_worker
      attr_reader :signature_worker
      attr_reader :code_workers

      attr_reader :response_handlers

      # There are four types of threads:
      #
      # 1. Main thread -- Reads messages from client
      # 2. Worker threads -- Reads messages from associated worker
      # 3. Reconciliation thread -- Receives message from worker threads, reconciles, processes, and forwards to write thread
      # 4. Write thread -- Writes messages to client
      #
      # We have two queues:
      #
      # 1. `recon_queue` is to pass messages from worker threads to reconciliation thread
      # 2. `write` thread is to pass messages to write thread
      #
      # Message passing: Client -> Server (Master) -> Worker
      #
      # 1. Client -> Server
      #   Master receives messages from the LSP client on main thread.
      #
      # 2. Master -> Worker
      #   Master writes messages to workers on main thread.
      #
      # Message passing: Worker -> Server (Master) -> (reconciliation queue) -> (write queue) -> Client
      #
      # 3. Worker -> Master
      #   Master receives messages on threads dedicated for each worker.
      #   The messages sent from workers are then forwarded to the reconciliation thread through reconciliation queue.
      #
      # 4. Server -> Client
      #   The reconciliation thread reads messages from reconciliation queue, does something, and finally sends messages to the client via write queue.
      #
      attr_reader :write_queue
      attr_reader :recon_queue

      include Utils

      class ResponseHandler
        attr_reader :workers

        attr_reader :request
        attr_reader :responses

        attr_reader :on_response_handlers
        attr_reader :on_completion_handlers

        def initialize(request:, workers:)
          @workers = []

          @request = request
          @responses = workers.each.with_object({}) do |worker, hash|
            hash[worker] = nil
          end

          @on_response_handlers = []
          @on_completion_handlers = []
        end

        def on_response(&block)
          on_response_handlers << block
        end

        def on_completion(&block)
          on_completion_handlers << block
        end

        def request_id
          request[:id]
        end

        def process_response(response, worker)
          responses[worker] = response

          on_response_handlers.each do |handler|
            handler[worker, response]
          end

          if completed?
            on_completion_handlers.each do |handler|
              handler[*responses.values]
            end
          end
        end

        def completed?
          responses.each_value.none?(&:nil?)
        end
      end

      def initialize(project:, reader:, writer:, interaction_worker:, signature_worker:, code_workers:, queue: Queue.new)
        @project = project
        @reader = reader
        @writer = writer
        @write_queue = queue
        @recon_queue = Queue.new
        @interaction_worker = interaction_worker
        @signature_worker = signature_worker
        @code_workers = code_workers
        @worker_to_paths = {}
        @shutdown_request_id = nil
        @response_handlers = {}
      end

      def start
        Steep.logger.tagged "master" do
          tags = Steep.logger.formatter.current_tags.dup

          Steep.logger.info "Registering all code to workers..."
          source_paths = project.all_source_files
          bin_size = (source_paths.size / code_workers.size) + 1
          source_paths.each_slice(bin_size).with_index do |paths, index|
            register_code_to_worker(paths, worker: code_workers[index])
          end

          worker_threads = []

          worker_threads << Thread.new do
            Steep.logger.formatter.push_tags(*tags, "from-worker@interaction")
            interaction_worker.reader.read do |message|
              process_message_from_worker(message, worker: interaction_worker)
            end
          end

          worker_threads << Thread.new do
            Steep.logger.formatter.push_tags(*tags, "from-worker@signature")
            signature_worker.reader.read do |message|
              process_message_from_worker(message, worker: signature_worker)
            end
          end

          code_workers.each do |worker|
            worker_threads << Thread.new do
              Steep.logger.formatter.push_tags(*tags, "from-worker@#{worker.name}")
              worker.reader.read do |message|
                process_message_from_worker(message, worker: worker)
              end
            end
          end

          worker_threads << Thread.new do
            Steep.logger.formatter.push_tags(*tags, "write")
            while message = write_queue.pop
              writer.write(message)
            end

            writer.io.close
          end

          worker_threads << Thread.new do
            Steep.logger.formatter.push_tags(*tags, "reconciliation")
            while (message, worker = recon_queue.pop)
              id = message[:id]
              handler = response_handlers[id] or raise

              Steep.logger.info "Processing response to #{handler.request[:method]}(#{id}) from #{worker.name}"

              handler.process_response(message, worker)

              if handler.completed?
                Steep.logger.info "Response to #{handler.request[:method]}(#{id}) completed"
                response_handlers.delete(id)
              end
            end
          end

          Steep.logger.tagged "main" do
            reader.read do |request|
              process_message_from_client(request) or break
            end

            worker_threads.each do |thread|
              thread.join
            end
          end
        end
      end

      def each_worker(&block)
        if block_given?
          yield interaction_worker
          yield signature_worker
          code_workers.each &block
        else
          enum_for :each_worker
        end
      end

      def process_message_from_client(message)
        Steep.logger.info "Received message #{message[:method]}(#{message[:id]})"
        id = message[:id]

        case message[:method]
        when "initialize"
          broadcast_request(message) do |handler|
            handler.on_completion do
              write_queue << {
                id: id,
                result: LSP::Interface::InitializeResult.new(
                  capabilities: LSP::Interface::ServerCapabilities.new(
                    text_document_sync: LSP::Interface::TextDocumentSyncOptions.new(
                      change: LSP::Constant::TextDocumentSyncKind::INCREMENTAL
                    ),
                    hover_provider: true,
                    completion_provider: LSP::Interface::CompletionOptions.new(
                      trigger_characters: [".", "@"]
                    ),
                    workspace_symbol_provider: true
                  )
                )
              }
            end
          end

        when "textDocument/didChange"
          update_source(message)

          uri = URI.parse(message[:params][:textDocument][:uri])
          path = project.relative_path(Pathname(uri.path))

          unless registered_path?(path)
            register_code_to_worker [path], worker: least_busy_worker()
          end

          broadcast_notification(message)

        when "textDocument/hover", "textDocument/completion"
          send_request(message, worker: interaction_worker) do |handler|
            handler.on_completion do |response|
              write_queue << response
            end
          end

        when "textDocument/open"
          # Ignores open notification

        when "workspace/symbol"
          send_request(message, worker: signature_worker) do |handler|
            handler.on_completion do |response|
              write_queue << response
            end
          end

        when "shutdown"
          broadcast_request(message) do |handler|
            handler.on_completion do |*_|
              write_queue << { id: id, result: nil}

              write_queue.close
              recon_queue.close
            end
          end

        when "exit"
          broadcast_notification(message)

          return false
        end

        true
      end

      def broadcast_notification(message)
        Steep.logger.info "Broadcasting notification #{message[:method]}"
        each_worker do |worker|
          worker << message
        end
      end

      def send_notification(message, worker:)
        Steep.logger.info "Sending notification #{message[:method]} to #{worker.name}"
        worker << message
      end

      def send_request(message, worker:)
        Steep.logger.info "Sending request #{message[:method]}(#{message[:id]}) to #{worker.name}"
        handler = ResponseHandler.new(request: message, workers: [worker])
        yield(handler) if block_given?
        response_handlers[handler.request_id] = handler

        worker << message
      end

      def broadcast_request(message)
        Steep.logger.info "Broadcasting request #{message[:method]}(#{message[:id]})"
        handler = ResponseHandler.new(request: message, workers: each_worker.to_a)
        yield(handler) if block_given?
        response_handlers[handler.request_id] = handler

        each_worker do |worker|
          worker << message
        end
      end

      def process_message_from_worker(message, worker:)
        case
        when message.key?(:id) && !message.key?(:method)
          # Response from worker
          Steep.logger.info "Received response #{message[:id]} from worker"
          recon_queue << [message, worker]
        when message.key?(:method) && !message.key?(:id)
          # Notification from worker
          Steep.logger.info "Received notification #{message[:method]} from worker"
          write_queue << message
        end
      end

      def paths_for(worker)
        worker_to_paths[worker] ||= Set[]
      end

      def least_busy_worker
        code_workers.min_by do |w|
          paths_for(w).size
        end
      end

      def registered_path?(path)
        worker_to_paths.each_value.any? {|set| set.include?(path) }
      end

      def register_code_to_worker(paths, worker:)
        paths_for(worker).merge(paths)

        send_notification(
          {
            method: "workspace/executeCommand",
            params: LSP::Interface::ExecuteCommandParams.new(
              command: "steep/registerSourceToWorker",
              arguments: paths.map do |path|
                "file://#{project.absolute_path(path)}"
              end
            )
          },
          worker: worker
        )
      end

      def kill
        each_worker do |worker|
          worker.kill
        end
      end
    end
  end
end
