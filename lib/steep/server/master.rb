module Steep
  module Server
    class Master
      LSP = LanguageServer::Protocol

      class ResultHandler
        attr_reader :request
        attr_reader :completion_handler
        attr_reader :response

        def initialize(request:)
          @request = request
          @response = nil
          @completion_handler = nil
          @completed = false
        end

        def process_response(message)
          if request[:id] == message[:id]
            completion_handler&.call(message)
            @response = message
            true
          else
            false
          end
        end

        def result
          response&.dig(:result)
        end

        def completed?
          !!@response
        end

        def on_completion(&block)
          @completion_handler = block
        end
      end

      class GroupHandler
        attr_reader :request
        attr_reader :handlers
        attr_reader :completion_handler

        def initialize()
          @handlers = {}
          @completion_handler = nil
        end

        def process_response(message)
          if handler = handlers[message[:id]]
            handler.process_response(message)

            if completed?
              completion_handler&.call(handlers.values)
            end

            true
          else
            false
          end
        end

        def completed?
          handlers.each_value.all? {|handler| handler.completed? }
        end

        def <<(handler)
          handlers[handler.request[:id]] = handler
        end

        def on_completion(&block)
          @completion_handler = block
        end
      end

      class ResultController
        attr_reader :handlers

        def initialize()
          @handlers = []
        end

        def <<(handler)
          @handlers << handler
        end

        def request_group()
          group = GroupHandler.new()
          yield group
          group
        end

        def process_response(message)
          handlers.each do |handler|
            return true if handler.process_response(message)
          end
          false
        ensure
          handlers.reject!(&:completed?)
        end
      end

      module MessageUtils
        def request?
          if method && id
            true
          else
            false
          end
        end

        def response?
          if id && !method
            true
          else
            false
          end
        end

        def notification?
          if method && !id
            true
          else
            false
          end
        end

        def method
          message[:method]
        end

        def id
          message[:id]
        end

        def result
          message[:result]
        end

        def params
          message[:params]
        end
      end

      ReceiveMessageJob = _ = Struct.new(:source, :message, keyword_init: true) do
        # @implements ReceiveMessageJob

        def response?
          message.key?(:id) && !message.key?(:method)
        end

        include MessageUtils
      end

      class SendMessageJob < Struct.new(:dest, :message, keyword_init: true)
        # @implements SendMessageJob

        def self.to_worker(worker, message:)
          new(dest: worker, message: message)
        end

        def self.to_client(message:)
          new(dest: :client, message: message)
        end

        include MessageUtils
      end

      attr_reader :project
      attr_reader :reader, :writer
      attr_reader :commandline_args

      attr_reader :interaction_worker
      attr_reader :typecheck_workers

      attr_reader :job_queue, :write_queue

      attr_reader :current_type_check_request
      attr_reader :refork_mutex
      attr_reader :controller
      attr_reader :result_controller

      attr_reader :initialize_params
      attr_accessor :typecheck_automatically
      attr_reader :start_type_checking_queue

      def initialize(project:, reader:, writer:, interaction_worker:, typecheck_workers:, queue: Queue.new, refork: false)
        @project = project
        @reader = reader
        @writer = writer
        @interaction_worker = interaction_worker
        @typecheck_workers = typecheck_workers
        @current_type_check_request = nil
        @typecheck_automatically = true
        @commandline_args = []
        @job_queue = queue
        @write_queue = SizedQueue.new(100)
        @refork_mutex = Mutex.new
        @need_to_refork = refork

        @controller = TypeCheckController.new(project: project)
        @result_controller = ResultController.new()
        @start_type_checking_queue = DelayQueue.new(delay: 0.3)
      end

      def start
        Steep.logger.tagged "master" do
          tags = Steep.logger.formatter.current_tags.dup

          # @type var worker_threads: Array[Thread]
          worker_threads = []

          if interaction_worker
            worker_threads << Thread.new do
              Steep.logger.formatter.push_tags(*tags, "from-worker@interaction")
              interaction_worker.reader.read do |message|
                job_queue << ReceiveMessageJob.new(source: interaction_worker, message: message)
              end
            end
          end

          typecheck_workers.each do |worker|
            worker_threads << Thread.new do
              Steep.logger.formatter.push_tags(*tags, "from-worker@#{worker.name}")
              worker.reader.read do |message|
                job_queue << ReceiveMessageJob.new(source: worker, message: message)
              end
            end
          end

          read_client_thread = Thread.new do
            reader.read do |message|
              job_queue << ReceiveMessageJob.new(source: :client, message: message)
              break if message[:method] == "exit"
            end
          end

          write_thread = Thread.new do
            Steep.logger.formatter.push_tags(*tags)
            Steep.logger.tagged "write" do
              while job = write_queue.deq
                # @type var job: SendMessageJob
                case job.dest
                when :client
                  Steep.logger.info { "Processing SendMessageJob: dest=client, method=#{job.message[:method] || "-"}, id=#{job.message[:id] || "-"}" }
                  writer.write job.message
                when WorkerProcess
                  refork_mutex.synchronize do
                    Steep.logger.info { "Processing SendMessageJob: dest=#{job.dest.name}, method=#{job.message[:method] || "-"}, id=#{job.message[:id] || "-"}" }
                    job.dest << job.message
                  end
                end
              end
            end
          end

          loop_thread = Thread.new do
            Steep.logger.formatter.push_tags(*tags)
            Steep.logger.tagged "main" do
              while job = job_queue.deq
                case job
                when ReceiveMessageJob
                  src = case job.source
                        when :client
                          :client
                        else
                          job.source.name
                        end
                  Steep.logger.tagged("ReceiveMessageJob(#{src}/#{job.message[:method]}/#{job.message[:id]})") do
                    if job.response? && result_controller.process_response(job.message)
                      # nop
                      Steep.logger.info { "Processed by ResultController" }
                    else
                      case job.source
                      when :client
                        process_message_from_client(job.message)

                        if job.message[:method] == "exit"
                          job_queue.close()
                        end
                      when WorkerProcess
                        process_message_from_worker(job.message, worker: job.source)
                      end
                    end
                  end
                when Proc
                  job.call()
                end
              end
            end
          end

          waiter = ThreadWaiter.new(each_worker.to_a) {|worker| worker.wait_thread }
          # @type var th: Thread & WorkerProcess::_ProcessWaitThread
          while th = _ = waiter.wait_one()
            if each_worker.any? { |worker| worker.pid == th.pid }
              break # The worker unexpectedly exited
            end
          end

          unless job_queue.closed?
            # Exit by error
            each_worker do |worker|
              worker.kill(force: true)
            end
            raise "Unexpected worker process exit"
          end

          write_queue.close()
          write_thread.join

          read_client_thread.join()
          worker_threads.each do |thread|
            thread.join
          end

          loop_thread.join
        end
      end

      def each_worker(&block)
        if block
          yield interaction_worker if interaction_worker
          typecheck_workers.each(&block)
        else
          enum_for :each_worker
        end
      end

      def pathname(uri)
        Steep::PathHelper.to_pathname(uri)
      end

      def assign_initialize_params(params)
        @initialize_params = params
      end

      def work_done_progress_supported?
        initialize_params or raise "`initialize` request is not receiged yet"
        initialize_params.dig(:capabilities, :window, :workDoneProgress) ? true : false
      end

      def file_system_watcher_supported?
        initialize_params or raise "`initialize` request is not receiged yet"
        initialize_params.dig(:capabilities, :workspace, :didChangeWatchedFiles, :dynamicRegistration) || false
      end

      def process_message_from_client(message)
        Steep.logger.info "Processing message from client: method=#{message[:method]}, id=#{message[:id]}"
        id = message[:id]

        case message[:method]
        when "initialize"
          assign_initialize_params(message[:params])

          result_controller << group_request do |group|
            each_worker do |worker|
              group << send_request(method: "initialize", params: message[:params], worker: worker)
            end

            group.on_completion do
              enqueue_write_job SendMessageJob.to_client(
                message: {
                  id: id,
                  result: LSP::Interface::InitializeResult.new(
                    capabilities: LSP::Interface::ServerCapabilities.new(
                      text_document_sync: LSP::Interface::TextDocumentSyncOptions.new(
                        change: LSP::Constant::TextDocumentSyncKind::INCREMENTAL,
                        open_close: true
                      ),
                      hover_provider: {
                        workDoneProgress: true,
                        partialResults: true,
                        partialResult: true
                      },
                      completion_provider: LSP::Interface::CompletionOptions.new(
                        trigger_characters: [".", "@", ":"],
                        work_done_progress: true
                      ),
                      signature_help_provider: {
                        triggerCharacters: ["("]
                      },
                      workspace_symbol_provider: true,
                      definition_provider: true,
                      declaration_provider: false,
                      implementation_provider: true,
                      type_definition_provider: true
                    ),
                    server_info: {
                      name: "steep",
                      version: VERSION
                    }
                  )
                }
              )

              progress = work_done_progress(SecureRandom.uuid)
              if typecheck_automatically
                progress.begin("Type checking", "loading projects...", request_id: fresh_request_id)
              end

              Steep.measure("Load files from disk...") do
                controller.load(command_line_args: commandline_args) do |input|
                  input.transform_values! do |content|
                    content.is_a?(String) or raise
                    if content.valid_encoding?
                      content
                    else
                      { text: Base64.encode64(content), binary: true }
                    end
                  end
                  broadcast_notification(CustomMethods::FileLoad.notification({ content: input }))
                end
              end

              if typecheck_automatically
                progress.end()
              end

              if file_system_watcher_supported?
                setup_file_system_watcher()
              end

              controller.changed_paths.clear()

              # if typecheck_automatically
              #   if request = controller.make_request(guid: progress.guid, include_unchanged: true, progress: progress)
              #     start_type_check(request: request, last_request: nil)
              #   end
              # end
            end
          end

        when "workspace/didChangeWatchedFiles"
          updated_watched_files = [] #: Array[Pathname]

          message[:params][:changes].each do |change|
            uri = change[:uri]
            type = change[:type]

            path = PathHelper.to_pathname!(uri)

            unless controller.priority_paths.include?(path)
              updated_watched_files << path

              controller.push_changes(path)

              case type
              when LSP::Constant::FileChangeType::CREATED, LSP::Constant::FileChangeType::CHANGED
                content = path.read
              when LSP::Constant::FileChangeType::DELETED
                content = ""
              end

              content or raise

              broadcast_notification(CustomMethods::FileReset.notification({ uri: uri, content: content }))
            end
          end

          if updated_watched_files.empty?
            Steep.logger.info { "Exit from workspace/didChangeWatchedFiles notification because all of the changed files are already open" }
            return
          end

          if typecheck_automatically
            start_type_checking_queue.execute do
              job_queue.push(
                -> do
                  last_request = current_type_check_request
                  guid = SecureRandom.uuid

                  start_type_check(
                    last_request: last_request,
                    progress: work_done_progress(guid),
                    needs_response: false
                  )
                end
              )
            end
          end

        when "textDocument/didChange"
          if path = pathname(message[:params][:textDocument][:uri])
            broadcast_notification(message)
            controller.push_changes(path)

            if typecheck_automatically
              start_type_checking_queue.execute do
                job_queue.push(
                  -> do
                    Steep.logger.info { "Starting type check from textDocument/didChange notification..." }

                    last_request = current_type_check_request
                    guid = SecureRandom.uuid

                    start_type_check(
                      last_request: last_request,
                      progress: work_done_progress(guid),
                      needs_response: false
                    )
                  end
                )
              end
            end
          end

        when "textDocument/didOpen"
          uri = message[:params][:textDocument][:uri]
          text = message[:params][:textDocument][:text]

          if path = pathname(uri)
            if target = project.group_for_path(path)
              controller.update_priority(open: path)
              # broadcast_notification(CustomMethods::FileReset.notification({ uri: uri, content: text }))

              start_type_checking_queue.execute do
                guid = SecureRandom.uuid
                start_type_check(last_request: current_type_check_request, progress: work_done_progress(guid), needs_response: true)
              end
            end
          end

        when "textDocument/didClose"
          if path = pathname(message[:params][:textDocument][:uri])
            controller.update_priority(close: path)
          end

        when "textDocument/hover", "textDocument/completion", "textDocument/signatureHelp"
          if interaction_worker
            if path = pathname(message[:params][:textDocument][:uri])
              result_controller << send_request(method: message[:method], params: message[:params], worker: interaction_worker) do |handler|
                handler.on_completion do |response|
                  enqueue_write_job SendMessageJob.to_client(
                    message: {
                      id: message[:id],
                      result: response[:result]
                    }
                  )
                end
              end
            else
              enqueue_write_job SendMessageJob.to_client(
                message: {
                  id: message[:id],
                  result: nil
                }
              )
            end
          end

        when "workspace/symbol"
          result_controller << group_request do |group|
            typecheck_workers.each do |worker|
              group << send_request(method: "workspace/symbol", params: message[:params], worker: worker)
            end

            group.on_completion do |handlers|
              result = handlers.flat_map(&:result)
              result.uniq!
              enqueue_write_job SendMessageJob.to_client(message: { id: message[:id], result: result })
            end
          end

        when CustomMethods::Stats::METHOD
          result_controller << group_request do |group|
            typecheck_workers.each do |worker|
              group << send_request(method: CustomMethods::Stats::METHOD, params: nil, worker: worker)
            end

            group.on_completion do |handlers|
              stats = handlers.flat_map(&:result) #: Server::CustomMethods::Stats::result
              enqueue_write_job SendMessageJob.to_client(
                message: CustomMethods::Stats.response(message[:id], stats)
              )
            end
          end

        when "textDocument/definition", "textDocument/implementation", "textDocument/typeDefinition"
          if path = pathname(message[:params][:textDocument][:uri])
            result_controller << group_request do |group|
              typecheck_workers.each do |worker|
                group << send_request(method: message[:method], params: message[:params], worker: worker)
              end

              group.on_completion do |handlers|
                links = handlers.flat_map(&:result)
                links.uniq!
                enqueue_write_job SendMessageJob.to_client(
                  message: {
                    id: message[:id],
                    result: links
                  }
                )
              end
            end
          else
            enqueue_write_job SendMessageJob.to_client(
              message: {
                id: message[:id],
                result: [] #: Array[untyped]
              }
            )
          end

        when CustomMethods::TypeCheck::METHOD
          id = message[:id]
          params = message[:params] #: CustomMethods::TypeCheck::params

          request = TypeCheckController::Request.new(guid: id, progress: work_done_progress(id))
          request.needs_response = true

          params[:code_paths].each do |target_name, path|
            request.code_paths << [target_name.to_sym, Pathname(path)]
          end
          params[:signature_paths].each do |target_name, path|
            request.signature_paths << [target_name.to_sym, Pathname(path)]
          end
          params[:library_paths].each do |target_name, path|
            request.library_paths << [target_name.to_sym, Pathname(path)]
          end

          start_type_check(request: request, last_request: nil)

        when CustomMethods::TypeCheckGroups::METHOD
          params = message[:params] #: CustomMethods::TypeCheckGroups::params

          groups = params.fetch(:groups)

          progress = work_done_progress(SecureRandom.uuid)
          progress.begin("Type checking #{groups.empty? ? "project" : groups.join(", ")}", request_id: fresh_request_id)

          request = controller.make_group_request(groups, progress: progress)
          request.needs_response = false
          start_type_check(request: request, last_request: current_type_check_request, report_progress_threshold: 0)

        when "$/ping"
          enqueue_write_job SendMessageJob.to_client(
            message: {
                id: message[:id],
                result: message[:params]
            }
          )

        when CustomMethods::Groups::METHOD
          groups = [] #: Array[String]

          project.targets.each do |target|
            unless target.source_pattern.empty? && target.signature_pattern.empty?
              groups << target.name.to_s
            end

            target.groups.each do |group|
              unless group.source_pattern.empty? && group.signature_pattern.empty?
                groups << "#{target.name}.#{group.name}"
              end
            end
          end

          enqueue_write_job(SendMessageJob.to_client(
            message: CustomMethods::Groups.response(message[:id], groups)
          ))

        when "shutdown"
          start_type_checking_queue.cancel

          result_controller << group_request do |group|
            each_worker do |worker|
              group << send_request(method: "shutdown", worker: worker)
            end

            group.on_completion do
              enqueue_write_job SendMessageJob.to_client(message: { id: message[:id], result: nil })
            end
          end

        when "exit"
          broadcast_notification(message)
        end
      end

      def process_message_from_worker(message, worker:)
        Steep.logger.tagged "#process_message_from_worker (worker=#{worker.name})" do
          Steep.logger.info { "Processing message from worker: method=#{message[:method] || "-"}, id=#{message[:id] || "*"}" }

          case
          when message.key?(:id) && !message.key?(:method)
            Steep.logger.tagged "response(id=#{message[:id]})" do
              Steep.logger.error { "Received unexpected response" }
              Steep.logger.debug { "result = #{message[:result].inspect}" }
            end
          when message.key?(:method) && !message.key?(:id)
            case message[:method]
            when CustomMethods::TypeCheck__Progress::METHOD
              params = message[:params] #: CustomMethods::TypeCheck__Progress::params
              target = project.targets.find {|target| target.name.to_s == params[:target] } or raise
              on_type_check_update(
                guid: params[:guid],
                path: Pathname(params[:path]),
                target: target,
                diagnostics: params[:diagnostics]
              )
            else
              # Forward other notifications
              enqueue_write_job SendMessageJob.to_client(message: message)
            end
          end
        end
      end

      def finish_type_check(request)
        request.work_done_progress.end()

        finished_at = Time.now
        duration = finished_at - request.started_at

        if request.needs_response
          enqueue_write_job(
            SendMessageJob.to_client(
              message: CustomMethods::TypeCheck.response(
                request.guid,
                {
                  guid: request.guid,
                  completed: request.finished?,
                  started_at: request.started_at.iso8601,
                  finished_at: finished_at.iso8601,
                  duration: duration.to_i
                }
              )
            )
          )
        else
          Steep.logger.debug { "Skip sending response to #{CustomMethods::TypeCheck::METHOD} request" }
        end
      end

      def start_type_check(request: nil, last_request:, progress: nil, include_unchanged: false, report_progress_threshold: 10, needs_response: nil)
        Steep.logger.tagged "#start_type_check(#{progress&.guid || request&.guid}, #{last_request&.guid}" do
          if last_request
            finish_type_check(last_request)
          end

          unless request
            progress or raise
            request = controller.make_request(guid: progress.guid, include_unchanged: include_unchanged, progress: progress) or return
            request.needs_response = needs_response ? true : false
          end

          if last_request
            request.merge!(last_request)
          end

          if request.total > report_progress_threshold
            request.report_progress!
          end

          if request.each_unchecked_target_path.to_a.empty?
            finish_type_check(request)
            @current_type_check_request = nil
            return
          end

          Steep.logger.info "Starting new progress..."

          @current_type_check_request = request

          if progress
            # If `request:` keyword arg is not given
            request.work_done_progress.begin("Type checking", request_id: fresh_request_id)
          end

          Steep.logger.info "Sending $/typecheck/start notifications"
          typecheck_workers.each do |worker|
            assignment = Services::PathAssignment.new(
              max_index: typecheck_workers.size,
              index: worker.index || raise
            )

            enqueue_write_job SendMessageJob.to_worker(
              worker,
              message: CustomMethods::TypeCheck__Start.notification(request.as_json(assignment: assignment))
            )
          end
        end
      end

      def on_type_check_update(guid:, path:, target:, diagnostics:)
        if current = current_type_check_request()
          if current.guid == guid
            current.checked(path, target)

            Steep.logger.info { "Request updated: checked=#{path}, unchecked=#{current.each_unchecked_code_target_path.size}, diagnostics=#{diagnostics&.size}" }

            percentage = current.percentage
            current.work_done_progress.report(percentage, "#{current.checked_paths.size}/#{current.total}") if current.report_progress

            push_diagnostics(path, diagnostics)

            if current.finished?
              finish_type_check(current)
              @current_type_check_request = nil
              refork_workers
            end
          end
        end
      end

      def refork_workers
        return unless @need_to_refork
        @need_to_refork = false

        Thread.new do
          Thread.current.abort_on_exception = true

          primary, *others = typecheck_workers
          primary or raise
          others.each do |worker|
            worker.index or raise

            refork_mutex.synchronize do
              refork_finished = Thread::Queue.new
              stdin_in, stdin_out = IO.pipe
              stdout_in, stdout_out = IO.pipe

              result_controller << send_refork_request(params: { index: worker.index, max_index: typecheck_workers.size }, worker: primary) do |handler|
                handler.on_completion do |response|
                  writer = LanguageServer::Protocol::Transport::Io::Writer.new(stdin_out)
                  reader = LanguageServer::Protocol::Transport::Io::Reader.new(stdout_in)

                  pid = response[:result][:pid]
                  # It does not need to wait worker process
                  # because the primary worker monitors it instead.
                  #
                  # @type var wait_thread: Thread & WorkerProcess::_ProcessWaitThread
                  wait_thread = _ = Thread.new { sleep }
                  wait_thread.define_singleton_method(:pid) { pid }

                  new_worker = WorkerProcess.new(reader:, writer:, stderr: nil, wait_thread:, name: "#{worker.name}-2", index: worker.index)
                  old_worker = typecheck_workers[worker.index] or raise

                  typecheck_workers[(new_worker.index or raise)] = new_worker

                  original_old_worker = old_worker.dup
                  old_worker.redirect_to new_worker

                  refork_finished << true

                  result_controller << send_request(method: 'shutdown', worker: original_old_worker) do |handler|
                    handler.on_completion do
                      send_request(method: 'exit', worker: original_old_worker)
                    end
                  end

                  Thread.new do
                    tags = Steep.logger.formatter.current_tags.dup
                    Steep.logger.formatter.push_tags(*tags, "from-worker@#{new_worker.name}")
                    new_worker.reader.read do |message|
                      job_queue << ReceiveMessageJob.new(source: new_worker, message: message)
                    end
                  end
                end
              end

              # The primary worker starts forking when it receives the IOs.
              primary.io_socket or raise
              primary.io_socket.send_io(stdin_in)
              primary.io_socket.send_io(stdout_out)
              stdin_in.close
              stdout_out.close

              refork_finished.pop
            end
          end
        end
      end

      def broadcast_notification(message)
        Steep.logger.info "Broadcasting notification #{message[:method]}"
        each_worker do |worker|
          enqueue_write_job SendMessageJob.new(dest: worker, message: message)
        end
      end

      def send_notification(message, worker:)
        Steep.logger.info "Sending notification #{message[:method]} to #{worker.name}"
        enqueue_write_job SendMessageJob.new(dest: worker, message: message)
      end

      def fresh_request_id
        SecureRandom.alphanumeric(10)
      end

      def send_request(method:, id: fresh_request_id(), params: nil, worker:, &block)
        Steep.logger.info "Sending request #{method}(#{id}) to #{worker.name}"

        # @type var message: lsp_request
        message = { method: method, id: id, params: params }
        ResultHandler.new(request: message).tap do |handler|
          yield handler if block
          enqueue_write_job SendMessageJob.to_worker(worker, message: message)
        end
      end

      def send_refork_request(id: fresh_request_id(), params:, worker:, &block)
        method = CustomMethods::Refork::METHOD
        Steep.logger.info "Sending request #{method}(#{id}) to #{worker.name}"

        # @type var message: lsp_request
        message = { method: method, id: id, params: params }
        ResultHandler.new(request: message).tap do |handler|
          yield handler if block

          job = SendMessageJob.to_worker(worker, message: message)
          case job.dest
          when WorkerProcess
            job.dest << job.message
          else
            raise "Unexpected destination: #{job.dest}"
          end
        end
      end

      def group_request()
        GroupHandler.new().tap do |group|
          yield group
        end
      end

      def kill
        each_worker do |worker|
          worker.kill
        end
      end

      def enqueue_write_job(job)
        Steep.logger.info { "Write_queue has #{write_queue.size} items"}
        write_queue.push(job) # steep:ignore InsufficientKeywordArguments
      end

      def work_done_progress(guid)
        if work_done_progress_supported?
          WorkDoneProgress.new(guid) do |message|
            enqueue_write_job SendMessageJob.to_client(message: message)
          end
        else
          WorkDoneProgress.new(guid) do |message|
            # nop
          end
        end
      end

      def push_diagnostics(path, diagnostics)
        if diagnostics
          write_queue.push SendMessageJob.to_client(
            message: {
              method: :"textDocument/publishDiagnostics",
              params: { uri: Steep::PathHelper.to_uri(path).to_s, diagnostics: diagnostics }
            }
          )
        end
      end

      def setup_file_system_watcher()
        patterns = [] #: Array[String]

        project.targets.each do |target|
          patterns.concat(paths_to_watch(target.source_pattern, extname: ".rb"))
          patterns.concat(paths_to_watch(target.signature_pattern, extname: ".rbs"))
          target.groups.each do |group|
            patterns.concat(paths_to_watch(group.source_pattern, extname: ".rb"))
            patterns.concat(paths_to_watch(group.signature_pattern, extname: ".rbs"))
          end
        end
        patterns.sort!
        patterns.uniq!

        Steep.logger.info { "Setting up didChangeWatchedFiles with pattern: #{patterns.inspect}" }

        enqueue_write_job SendMessageJob.to_client(
          message: {
            id: SecureRandom.uuid,
            method: "client/registerCapability",
            params: {
              registrations: [
                {
                  id: SecureRandom.uuid,
                  method: "workspace/didChangeWatchedFiles",
                  registerOptions: {
                    watchers: patterns.map do |pattern|
                      { globPattern: pattern }
                    end
                  }
                }
              ]
            }
          }
        )
      end

      def paths_to_watch(pattern, extname:)
        result = [] #: Array[String]

        pattern.patterns.each do |pat|
          path = project.base_dir + pat
          result << path.to_s unless path.directory?
        end
        pattern.prefixes.each do |pat|
          path = project.base_dir + pat
          result << (path + "**/*#{extname}").to_s unless path.file?
        end

        result
      end
    end
  end
end
