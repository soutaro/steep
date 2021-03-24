module Steep
  module Server
    class Master
      class TypeCheckRequest
        attr_reader :guid
        attr_reader :library_paths
        attr_reader :signature_paths
        attr_reader :code_paths
        attr_reader :priority_paths
        attr_reader :checked_paths

        def initialize(guid:)
          @guid = guid
          @library_paths = Set[]
          @signature_paths = Set[]
          @code_paths = Set[]
          @priority_paths = Set[]
          @checked_paths = Set[]
        end

        def uri(path)
          URI.parse(path.to_s).tap do |uri|
            uri.scheme = "file"
          end
        end

        def as_json(assignment:)
          {
            guid: guid,
            library_uris: library_paths.grep(assignment).map {|path| uri(path).to_s },
            signature_uris: signature_paths.grep(assignment).map {|path| uri(path).to_s },
            code_uris: code_paths.grep(assignment).map {|path| uri(path).to_s },
            priority_uris: priority_paths.map {|path| uri(path).to_s }
          }
        end

        def total
          library_paths.size + signature_paths.size + code_paths.size
        end

        def percentage
          checked_paths.size * 100 / total
        end

        def all_paths
          library_paths + signature_paths + code_paths
        end

        def checking_path?(path)
          library_paths.include?(path) ||
            signature_paths.include?(path) ||
            code_paths.include?(path)
        end

        def checked(path)
          raise unless checking_path?(path)
          checked_paths << path
        end

        def finished?
          unchecked_paths.empty?
        end

        def unchecked_paths
          all_paths - checked_paths
        end

        def unchecked_code_paths
          code_paths - checked_paths
        end

        def unchecked_library_paths
          library_paths - checked_paths
        end

        def unchecked_signature_paths
          signature_paths - checked_paths
        end
      end

      class TypeCheckController
        attr_reader :project
        attr_reader :priority_paths
        attr_reader :changed_paths
        attr_reader :target_paths

        class TargetPaths
          attr_reader :project
          attr_reader :target
          attr_reader :code_paths
          attr_reader :signature_paths
          attr_reader :library_paths

          def initialize(project:, target:)
            @project = project
            @target = target
            @code_paths = Set[]
            @signature_paths = Set[]
            @library_paths = Set[]
          end

          def all_paths
            code_paths + signature_paths + library_paths
          end

          def library_path?(path)
            library_paths.include?(path)
          end

          def signature_path?(path)
            signature_paths.include?(path)
          end

          def code_path?(path)
            code_paths.include?(path)
          end

          def add(path)
            return if library_path?(path) || signature_path?(path) || code_path?(path)

            relative_path = project.relative_path(path)

            case
            when target.source_pattern =~ relative_path
              code_paths << path
            when target.signature_pattern =~ relative_path
              signature_paths << path
            else
              library_paths << path
            end
          end

          alias << add
        end

        def initialize(project:)
          @project = project
          @priority_paths = Set[]
          @changed_paths = Set[]
          @target_paths = project.targets.each.map {|target| TargetPaths.new(project: project, target: target) }
        end

        def load(command_line_args:)
          loader = Services::FileLoader.new(base_dir: project.base_dir)

          target_paths.each do |paths|
            target = paths.target

            signature_service = Services::SignatureService.load_from(target.new_env_loader(project: project))
            paths.library_paths.merge(signature_service.env_rbs_paths)

            loader.each_path_in_patterns(target.source_pattern, command_line_args) do |path|
              paths.code_paths << project.absolute_path(path)
            end
            loader.each_path_in_patterns(target.signature_pattern) do |path|
              paths.signature_paths << project.absolute_path(path)
            end

            changed_paths.merge(paths.all_paths)
          end
        end

        def push_changes(path)
          return if target_paths.any? {|paths| paths.library_path?(path) }

          target_paths.each {|paths| paths << path }

          if target_paths.any? {|paths| paths.code_path?(path) || paths.signature_path?(path) }
            changed_paths << path
          end
        end

        def update_priority(open: nil, close: nil)
          path = open || close

          target_paths.each {|paths| paths << path }

          case
          when open
            priority_paths << path
          when close
            priority_paths.delete path
          end
        end

        def make_request(guid: SecureRandom.uuid, last_request: nil, include_unchanged: false)
          return if changed_paths.empty? && !include_unchanged

          TypeCheckRequest.new(guid: guid).tap do |request|
            if last_request
              request.library_paths.merge(last_request.unchecked_library_paths)
              request.signature_paths.merge(last_request.unchecked_signature_paths)
              request.code_paths.merge(last_request.unchecked_code_paths)
            end

            if include_unchanged
              target_paths.each do |paths|
                request.signature_paths.merge(paths.signature_paths)
                request.library_paths.merge(paths.library_paths)
                request.code_paths.merge(paths.code_paths)
              end
            else
              updated_paths = target_paths.select {|paths| changed_paths.intersect?(paths.all_paths) }

              updated_paths.each do |paths|
                case
                when paths.signature_paths.intersect?(changed_paths)
                  request.signature_paths.merge(paths.signature_paths)
                  request.library_paths.merge(paths.library_paths)
                  request.code_paths.merge(paths.code_paths)
                when paths.code_paths.intersect?(changed_paths)
                  request.code_paths.merge(paths.code_paths & changed_paths)
                end
              end
            end

            request.priority_paths.merge(priority_paths)

            changed_paths.clear()
          end
        end
      end

      LSP = LanguageServer::Protocol

      attr_reader :steepfile
      attr_reader :project
      attr_reader :reader, :writer
      attr_reader :commandline_args

      attr_reader :interaction_worker
      attr_reader :typecheck_workers

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
      attr_reader :read_worker_queue

      attr_reader :current_type_check_request
      attr_reader :controller

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

      attr_accessor :typecheck_automatically

      def initialize(project:, reader:, writer:, interaction_worker:, typecheck_workers:, queue: Queue.new)
        @project = project
        @reader = reader
        @writer = writer
        @write_queue = queue
        @recon_queue = Queue.new
        @read_worker_queue = Queue.new
        @interaction_worker = interaction_worker
        @typecheck_workers = typecheck_workers
        @shutdown_request_id = nil
        @response_handlers = {}
        @current_type_check_request = nil
        @typecheck_automatically = true
        @commandline_args = []

        @controller = TypeCheckController.new(project: project)
      end

      def start_type_check(request, last_request:, start_progress:)
        return unless request

        if last_request
          write_queue << {
            method: "$/progress",
            params: {
              token: last_request.guid,
              value: { kind: "end" }
            }
          }
        end

        if start_progress
          @current_type_check_request = request

          write_queue << {
            id: (Time.now.to_f * 1000).to_i,
            method: "window/workDoneProgress/create",
            params: { token: request.guid }
          }

          write_queue << {
            method: "$/progress",
            params: {
              token: request.guid,
              value: { kind: "begin", title: "Type checking", percentage: 0 }
            }
          }

          if request.finished?
            write_queue << {
              method: "$/progress",
              params: { token: request.guid, value: { kind: "end" } }
            }
          end
        else
          @current_type_check_request = nil
        end

        typecheck_workers.each do |worker|
          assignment = Services::PathAssignment.new(max_index: typecheck_workers.size, index: worker.index)

          worker << {
            method: "$/typecheck/start",
            params: request.as_json(assignment: assignment)
          }
        end
      end

      def on_type_check_update(guid:, path:)
        if current = current_type_check_request()
          if current.guid == guid
            current.checked(path)
            percentage = current.percentage
            value = if percentage == 100
                      { kind: "end" }
                    else
                      progress_string = ("▮"*(percentage/5)) + ("▯"*(20 - percentage/5))
                      { kind: "report", percentage: percentage, message: "#{progress_string} (#{percentage}%)" }
                    end

            write_queue << {
              method: "$/progress",
              params: { token: current.guid, value: value }
            }

            @current_type_check_request = nil if current.finished?
          end
        end
      end

      def start
        Steep.logger.tagged "master" do
          tags = Steep.logger.formatter.current_tags.dup

          read_worker_thread = Thread.new do
            Steep.logger.formatter.push_tags(*tags, "read-worker")
            while (message, worker = read_worker_queue.pop)
              process_message_from_worker(message, worker: worker)
            end
          end

          worker_threads = []

          if interaction_worker
            worker_threads << Thread.new do
              Steep.logger.formatter.push_tags(*tags, "from-worker@interaction")
              interaction_worker.reader.read do |message|
                read_worker_queue << [message, interaction_worker]
              end
            end
          end

          typecheck_workers.each do |worker|
            worker_threads << Thread.new do
              Steep.logger.formatter.push_tags(*tags, "from-worker@#{worker.name}")
              worker.reader.read do |message|
                read_worker_queue << [message, worker]
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

            read_worker_queue.close()

            read_worker_thread.join()
          end
        end
      end

      def each_worker(&block)
        if block_given?
          yield interaction_worker if interaction_worker
          typecheck_workers.each &block
        else
          enum_for :each_worker
        end
      end

      def pathname(uri)
        Pathname(URI.parse(uri).path)
      end

      def process_message_from_client(message)
        Steep.logger.info "Received message #{message[:method]}(#{message[:id]})"
        id = message[:id]

        case message[:method]
        when "initialize"
          broadcast_request(message) do |handler|
            handler.on_completion do
              controller.load(command_line_args: commandline_args)

              write_queue << {
                id: id,
                result: LSP::Interface::InitializeResult.new(
                  capabilities: LSP::Interface::ServerCapabilities.new(
                    text_document_sync: LSP::Interface::TextDocumentSyncOptions.new(
                      change: LSP::Constant::TextDocumentSyncKind::INCREMENTAL,
                      save: true,
                      open_close: true
                    ),
                    hover_provider: true,
                    completion_provider: LSP::Interface::CompletionOptions.new(
                      trigger_characters: [".", "@"]
                    ),
                    workspace_symbol_provider: true
                  )
                )
              }

              if typecheck_automatically
                request = controller.make_request()
                start_type_check(
                  request,
                  last_request: current_type_check_request,
                  start_progress: request.total > 10
                )
              end
            end
          end

        when "textDocument/didChange"
          broadcast_notification(message)
          path = pathname(message[:params][:textDocument][:uri])
          controller.push_changes(path)

        when "textDocument/didSave"
          if typecheck_automatically
            request = controller.make_request()
            start_type_check(
              request,
              last_request: current_type_check_request,
              start_progress: request.total > 10
            )
          end

        when "textDocument/didOpen"
          path = pathname(message[:params][:textDocument][:uri])
          controller.update_priority(open: path)

        when "textDocument/didClose"
          path = pathname(message[:params][:textDocument][:uri])
          controller.update_priority(close: path)

        when "textDocument/hover", "textDocument/completion"
          if interaction_worker
            send_request(message, worker: interaction_worker) do |handler|
              handler.on_completion do |response|
                write_queue << response
              end
            end
          end

        when "workspace/symbol"
          send_request(message, workers: typecheck_workers) do |handler|
            handler.on_completion do |*responses|
              result = responses.flat_map {|resp| resp[:result] || [] }

              write_queue << {
                id: handler.request_id,
                result: result
              }
            end
          end

        when "workspace/executeCommand"
          case message[:params][:command]
          when "steep/stats"
            send_request(message, workers: typecheck_workers) do |handler|
              handler.on_completion do |*responses|
                stats = responses.flat_map {|resp| resp[:result] }
                write_queue << {
                  id: handler.request_id,
                  result: stats
                }
              end
            end
          end

        when "$/typecheck"
          request = controller.make_request(guid: message[:params][:guid], include_unchanged: true)
          start_type_check(
            request,
            last_request: current_type_check_request,
            start_progress: true
          )

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

      def send_request(message, worker: nil, workers: [])
        workers << worker if worker

        Steep.logger.info "Sending request #{message[:method]}(#{message[:id]}) to #{workers.map(&:name).join(", ")}"
        handler = ResponseHandler.new(request: message, workers: workers)
        yield(handler) if block_given?
        response_handlers[handler.request_id] = handler

        workers.each do |w|
          w << message
        end
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
          Steep.logger.debug { "Received response #{message[:id]} from worker" }
          recon_queue << [message, worker]
        when message.key?(:method) && !message.key?(:id)
          # Notification from worker
          Steep.logger.debug { "Received notification #{message[:method]} from worker" }

          case message[:method]
          when "$/typecheck/progress"
            on_type_check_update(
              guid: message[:params][:guid],
              path: Pathname(message[:params][:path])
            )
          else
            write_queue << message
          end
        end
      end

      def kill
        each_worker do |worker|
          worker.kill
        end
      end
    end
  end
end
