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

      attr_reader :launcher
      attr_reader :worker_threads
      attr_reader :worker_waiter

      attr_reader :job_queue, :write_queue

      attr_reader :current_type_check_request
      attr_reader :controller
      attr_reader :result_controller

      attr_reader :initialize_params
      attr_accessor :typecheck_automatically
      attr_reader :start_type_checking_queue

      attr_reader :type_check_database
      attr_reader :goto_resolver

      # Type check requests waiting for the current type check to finish
      attr_reader :pending_typecheck_requests

      # Callbacks to be called when no type check is running anymore
      attr_reader :typecheck_quiescent_callbacks
      attr_reader :environment_queue
      attr_reader :pending_typecheck_jobs
      attr_reader :typecheck_jobs_in_flight
      attr_reader :signature_paths_to_validate
      attr_reader :exiting_workers

      TYPECHECK_JOBS_PER_WORKER = 2

      WORKSPACE_SYMBOL_KINDS = {
        class: LSP::Constant::SymbolKind::CLASS,
        module: LSP::Constant::SymbolKind::MODULE,
        interface: LSP::Constant::SymbolKind::INTERFACE,
        type_alias: LSP::Constant::SymbolKind::ENUM,
        constant: LSP::Constant::SymbolKind::CONSTANT,
        global: LSP::Constant::SymbolKind::VARIABLE,
        method: LSP::Constant::SymbolKind::METHOD,
        attribute: LSP::Constant::SymbolKind::PROPERTY
      } #: Hash[TypeCheckDatabase::Entry::kind, LSP::Constant::SymbolKind::t]

      def initialize(project:, reader:, writer:, launcher:, queue: Queue.new)
        @project = project
        @reader = reader
        @writer = writer
        @launcher = launcher
        @worker_threads = []
        @worker_waiter = ThreadWaiter.new()
        @running = false
        @current_type_check_request = nil
        @typecheck_automatically = true
        @commandline_args = []
        @job_queue = queue
        @write_queue = SizedQueue.new(100)
        @environment_queue = Thread::Queue.new
        @pending_typecheck_jobs = []
        @typecheck_jobs_in_flight = {}
        @interaction_count = 0
        @signature_paths_to_validate = Set[]
        @environment_generation = 0
        @exiting_workers = Set[].compare_by_identity
        @exited_wait_threads = Set[].compare_by_identity
        @exited_wait_threads_mutex = Mutex.new
        @shutting_down = false
        @typecheck_quiescent_callbacks = []
        @pending_typecheck_requests = []
        @project_file_mtimes = nil
        @command_socket_requests = {}
        @command_socket_mutex = Mutex.new

        @controller = TypeCheckController.new(project: project)
        @result_controller = ResultController.new()
        @start_type_checking_queue = DelayQueue.new(delay: 0.3)
        @type_check_database = TypeCheckDatabase.new()
        @goto_resolver = GotoResolver.new(database: @type_check_database)
      end

      def start
        Steep.logger.tagged "master" do
          tags = Steep.logger.current_tags.dup
          @logger_tags = tags
          @running = true

          read_client_thread = Thread.new do
            reader.read do |message|
              job_queue << ReceiveMessageJob.new(source: :client, message: message)
              break if message[:method] == "exit"
            end
          end

          write_thread = Thread.new do
            Steep.logger.push_tags(*tags)
            Steep.logger.tagged "write" do
              while job = write_queue.deq
                # @type var job: SendMessageJob
                case job.dest
                when :client
                  Steep.logger.info { "Processing SendMessageJob: dest=client, method=#{job.message[:method] || "-"}, id=#{job.message[:id] || "-"}" }
                  write_message_to_client(job.message)
                when WorkerProcess
                  Steep.logger.info { "Processing SendMessageJob: dest=#{job.dest.name}, method=#{job.message[:method] || "-"}, id=#{job.message[:id] || "-"}" }
                  job.dest << job.message
                end
              end
            end
          end

          environment_thread = Thread.new do
            Steep.logger.push_tags(*tags)
            Steep.logger.tagged "environment" do
              while job = environment_queue.deq
                begin
                  job.call()
                rescue => exn
                  Steep.log_error(exn)
                end
              end
            end
          end

          loop_thread = Thread.new do
            Steep.logger.push_tags(*tags)
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

          # Returns when a worker process exits, or the main loop stops, but a retired worker is told to exit
          worker_waiter << loop_thread
          while thread = worker_waiter.wait_one()
            break unless @exited_wait_threads_mutex.synchronize { @exited_wait_threads.include?(thread) }
          end

          unless job_queue.closed?
            # A worker process exited, or the main loop stopped, before the client sent `exit`
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

          environment_queue.close()
          environment_thread.join

          launcher.stop
        end
      end

      def typecheck_workers
        launcher.typecheck_workers
      end

      def start_workers
        service = controller.type_check_service or raise "The project is not loaded yet"

        case launcher
        when SpawnLauncher
          Steep.measure("Starting the workers...") do
            launcher.start(service)
          end
          start_worker_threads()

          # The workers receive the files of the project, and the environments follow them in the background
          update_environment()

        when ForkLauncher
          # The workers are forked from the environments with the files of the project. The main loop updates the
          # environments itself, because the environment thread has no job yet, and nothing can run without the workers.
          changes = controller.pop_file_changes
          Steep.measure("Updating the environments with #{changes.size} files") do
            service.update(changes: changes)
          end
          warm_definitions(service)

          Steep.measure("Forking the workers...") do
            launcher.start(service)
          end
          start_worker_threads()

          signature_files = signature_files_in(changes)
          environment_queue << -> { index_signatures(service, signature_files) }
        end
      end

      def start_worker_threads
        if @running
          typecheck_workers.each do |worker|
            start_worker_thread(worker)
          end
        end
      end

      def start_worker_thread(worker)
        tags = @logger_tags || []

        worker_threads << Thread.new do
          Steep.logger.push_tags(*tags, "from-worker@#{worker.name}")
          worker.reader.read do |message|
            enqueue_worker_message(worker, message)
          end

          # The worker has exited
          job_queue << -> { close_exited_worker(worker) }
        rescue ClosedQueueError
          # The server is exiting
        end

        worker_waiter << worker.wait_thread
      end

      def close_exited_worker(worker)
        launcher = self.launcher

        if launcher.is_a?(ForkLauncher) && exiting_workers.delete?(worker)
          worker.reader.close
          worker.writer.close
          launcher.remove_retired_worker(worker)
          typecheck_jobs_in_flight.delete(worker)
        end
      end

      def enqueue_worker_message(worker, message)
        job_queue << ReceiveMessageJob.new(source: worker, message: message)
      rescue ClosedQueueError
        # The server is exiting: the worker finished its last job after `exit`, and the message is left behind
      end

      def each_worker(&block)
        if block
          typecheck_workers.each(&block)

          launcher = self.launcher
          if launcher.is_a?(ForkLauncher)
            launcher.retired_workers.each(&block)
          end
        else
          enum_for :each_worker
        end
      end

      def retiring_workers
        launcher = self.launcher

        if launcher.is_a?(ForkLauncher)
          launcher.retired_workers.reject { exiting_workers.include?(_1) }
        else
          []
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

      def related_information_supported?
        initialize_params or raise "`initialize` request is not receiged yet"
        initialize_params.dig(:capabilities, :textDocument, :publishDiagnostics, :relatedInformation) ? true : false
      end

      def process_message_from_client(message)
        Steep.logger.info "Processing message from client: method=#{message[:method]}, id=#{message[:id]}"
        id = message[:id]

        case message[:method]
        when "initialize"
          assign_initialize_params(message[:params])

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
            controller.load(command_line_args: commandline_args)
          end

          start_workers()

          index_library_signatures()

          if typecheck_automatically
            progress.end()
          end

          reset_project_file_mtimes()

          if file_system_watcher_supported?
            setup_file_system_watcher()
          end

          # controller.changed_paths.clear()

          # if typecheck_automatically
          #   if request = controller.make_request(guid: progress.guid, include_unchanged: true, progress: progress)
          #     start_type_check(request: request, last_request: nil)
          #   end
          # end

        when "workspace/didChangeWatchedFiles"
          updated_watched_files = [] #: Array[Pathname]

          message[:params][:changes].each do |change|
            uri = change[:uri]
            type = change[:type]

            path = PathHelper.to_pathname!(uri)

            unless controller.open_paths.include?(path)
              updated_watched_files << path
              record_project_file_mtime(path)

              case type
              when LSP::Constant::FileChangeType::CREATED, LSP::Constant::FileChangeType::CHANGED
                content = path.read
              when LSP::Constant::FileChangeType::DELETED
                content = ""
              end

              content or raise

              case
              when controller.code_path?(path)
                controller.add_dirty_code_path(path, content)
              when controller.signature_path?(path)
                controller.add_dirty_signature_path(path, content)
              when controller.inline_path?(path)
                controller.add_dirty_inline_path(path, content)
              end
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
            Steep.logger.debug { path.to_s }

            changes = Services::ContentChange.from_lsp(message[:params][:contentChanges])

            case
            when controller.code_path?(path)
              Steep.logger.debug { "code_path?" }
              controller.add_dirty_code_path(path, changes)
            when controller.signature_path?(path)
              Steep.logger.debug { "signature_path?" }
              controller.add_dirty_signature_path(path, changes)
            when controller.inline_path?(path)
              Steep.logger.debug { "inline_path?" }
              controller.add_dirty_inline_path(path, changes)
            end

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
              controller.open_path(path)
              controller.push_file_change(path, text) if text

              start_type_checking_queue.execute do
                guid = SecureRandom.uuid
                start_type_check(last_request: current_type_check_request, progress: work_done_progress(guid), needs_response: true)
              end
            end
          end

        when "textDocument/didClose"
          if path = pathname(message[:params][:textDocument][:uri])
            controller.close_path(path)
          end

        when "textDocument/hover", "textDocument/completion", "textDocument/signatureHelp"
          interaction =
            case message[:method]
            when "textDocument/hover"
              -> (provider, path, line, column) { provider.hover(path: path, line: line, column: column) }
            when "textDocument/completion"
              trigger = message[:params].dig(:context, :triggerCharacter) #: String?
              -> (provider, path, line, column) { provider.completion(path: path, line: line, column: column, trigger: trigger) }
            else
              -> (provider, path, line, column) { provider.signature_help(path: path, line: line, column: column) }
            end #: ^(InteractionProvider, Pathname, Integer, Integer) -> interaction_result?

          run_interaction(message, interaction) do |result|
            respond_to_interaction(message, result)
          end

        when "workspace/symbol"
          query = message[:params][:query] #: String
          enqueue_write_job SendMessageJob.to_client(message: { id: id, result: workspace_symbol_result(query) })

        when CustomMethods::Stats::METHOD
          enqueue_write_job SendMessageJob.to_client(
            message: CustomMethods::Stats.response(message[:id], stats_result())
          )

        when "textDocument/definition", "textDocument/implementation", "textDocument/typeDefinition"
          kind =
            case message[:method]
            when "textDocument/definition"
              :definition
            when "textDocument/implementation"
              :implementation
            else
              :type_definition
            end #: GotoResolver::kind

          path = pathname(message[:params][:textDocument][:uri])
          from =
            if path && (controller.files.signature_paths.registered_path?(path) || controller.files.library_path?(path))
              :rbs
            else
              :ruby
            end #: GotoResolver::from

          interaction = -> (provider, path, line, column) { provider.source_symbol(path: path, line: line, column: column) } #: ^(InteractionProvider, Pathname, Integer, Integer) -> InteractionProvider::SourceSymbol::result

          run_interaction(message, interaction) do |result|
            # The symbols are looked up in the database, on the main loop
            job_queue << -> do
              locations =
                if result
                  goto_resolver.goto(kind: kind, from: from, result: result)
                else
                  [] #: Array[GotoResolver::location]
                end

              enqueue_write_job SendMessageJob.to_client(message: { id: message[:id], result: locations })
            end
          end

        when CustomMethods::Query__Definition::METHOD
          params = message[:params] #: CustomMethods::Query__Definition::params
          enqueue_write_job SendMessageJob.to_client(
            message: CustomMethods::Query__Definition.response(message[:id], goto_resolver.query_definition(params[:name]))
          )

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
          params[:inline_paths].each do |target_name, path|
            request.inline_paths << [target_name.to_sym, Pathname(path)]
          end

          start_type_check(request: request, last_request: current_type_check_request)

        when CustomMethods::TypeCheckGroups::METHOD
          params = message[:params] #: CustomMethods::TypeCheckGroups::params

          groups = params.fetch(:groups)

          progress = work_done_progress(SecureRandom.uuid)
          progress.begin("Type checking #{groups.empty? ? "project" : groups.join(", ")}", request_id: fresh_request_id)

          if groups.empty?
            request = controller.make_all_request(progress: progress)
          else
            request = controller.make_group_request(groups, progress: progress)
          end

          request.needs_response = false
          start_type_check(request: request, last_request: current_type_check_request, report_progress_threshold: 0)

        when CustomMethods::Query__Diagnostics::METHOD
          id = message[:id]
          params = message[:params] #: CustomMethods::Query__Diagnostics::params
          paths = params[:paths]

          run_when_typecheck_quiescent do
            collect_query_diagnostics(id, paths)
          end

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
          @shutting_down = true
          start_type_checking_queue.cancel

          # The workers stop at `exit`
          enqueue_write_job SendMessageJob.to_client(message: { id: message[:id], result: nil })

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
            # Forward notifications from the workers to the client
            enqueue_write_job SendMessageJob.to_client(message: message)
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
          if (current = current_type_check_request) && typecheck_request_from_command_socket?(current)
            # Never supersede a type check that a command socket client is waiting for
            if request
              Steep.logger.info { "Queueing type check request #{request.guid} until the command socket request finishes" }
              pending_typecheck_requests << request
            else
              Steep.logger.info { "Deferring automatic type checking until the command socket request finishes" }
            end
            return
          end

          update_environment()

          if last_request
            finish_type_check(last_request)
          end

          unless request
            progress or raise
            request =
              if include_unchanged
                controller.make_all_request(guid: progress.guid, progress: progress)
              else
                controller.make_request(guid: progress.guid, progress: progress)
              end

            return unless request

            request.needs_response = needs_response ? true : false
          end

          if last_request
            request.merge!(last_request)
          end

          Steep.logger.debug {
            {
              code_paths: request.code_paths.map { _1[1].to_s },
              signature_paths: request.signature_paths.map { _1[1].to_s },
              inline_paths: request.inline_paths.map { _1[1].to_s }
            }.inspect
          }

          if request.total > report_progress_threshold
            request.report_progress!
          end

          if request.each_unchecked_target_path.to_a.empty?
            finish_type_check(request)
            @current_type_check_request = nil
            dispatch_typecheck_jobs()
            return
          end

          Steep.logger.info "Starting new progress..."

          @current_type_check_request = request

          if progress
            # If `request:` keyword arg is not given
            request.work_done_progress.begin("Type checking", request_id: fresh_request_id)
          end

          Steep.logger.info "Dispatching the type check jobs"

          jobs = request.jobs
          jobs.delete_if do |kind, target_name, path|
            if kind == :signature && signature_paths_to_validate.include?(path)
              validate_signature_on_environment(request, target_name, path)
              true
            end
          end

          @pending_typecheck_jobs = jobs
          dispatch_typecheck_jobs()
        end
      end

      def dispatch_typecheck_jobs
        return if @shutting_down
        request = current_type_check_request or return

        loop do
          workers = typecheck_workers.select {|worker| typecheck_jobs_in_flight.fetch(worker, 0) < TYPECHECK_JOBS_PER_WORKER }
          break if workers.empty?

          workers.each do |worker|
            job = pending_typecheck_jobs.shift or return
            send_typecheck_job(worker, request, job)
          end
        end
      end

      def index_library_signatures
        service = controller.type_check_service or return

        library_files = [] #: Array[[Symbol, Pathname]]
        project.targets.each do |target|
          controller.files.each_library_path(target) do |path|
            library_files << [target.name, path]
          end
        end

        environment_queue << -> { index_signatures(service, library_files) }
      end

      def index_signatures(service, target_files)
        return if target_files.empty?

        updates = [] #: Array[[Symbol, Pathname, Array[TypeCheckDatabase::Entry]]]

        target_files.group_by { |target_name, _| target_name }.each do |target_name, files|
          signature_service = service.signature_services.fetch(target_name)

          # The index of the last loaded signatures would have stale locations
          next unless signature_service.status.is_a?(Services::SignatureService::LoadedStatus)

          # The buffer of a library file is named by its absolute path, and the one of a project file by its relative path
          buffer_paths = files.to_h do |_, path|
            [signature_service.env_rbs_paths.include?(path) ? path : project.relative_path(path), path]
          end #: Hash[Pathname, Pathname]

          Steep.measure("Indexing #{files.size} files of #{target_name}") do
            entries = TypeCheckDatabase.rbs_entries_by_path(signature_service.latest_env, paths: Set.new(buffer_paths.each_key))
            buffer_paths.each do |buffer_path, path|
              updates << [target_name, path, entries.fetch(buffer_path, [])]
            end
          end
        end

        job_queue << -> do
          updates.each do |target_name, path, entries|
            type_check_database.update_rbs(path: path, target: target_name, entries: entries)
          end
        end
      rescue ClosedQueueError
        # The main loop has stopped
      end

      def send_typecheck_job(worker, request, job)
        kind, target_name, path = job
        target = project.targets.find {|target| target.name == target_name } or raise "Unknown target: #{target_name}"

        kind_string =
          case kind
          when :code
            "code"
          when :signature
            "signature"
          when :library
            "library"
          when :inline
            "inline"
          end #: CustomMethods::TypeCheck__File::kind

        params = {
          guid: request.guid,
          kind: kind_string,
          target: target_name.to_s,
          uri: PathHelper.to_uri(path).to_s
        } #: CustomMethods::TypeCheck__File::params

        if kind == :code || kind == :inline
          if file = controller.file_contents.fetch(project.relative_path(path), nil)
            params[:content] = wire_content(file.text)
          end
        end

        typecheck_jobs_in_flight[worker] = typecheck_jobs_in_flight.fetch(worker, 0) + 1

        result_controller << send_request(method: CustomMethods::TypeCheck__File::METHOD, params: params, worker: worker) do |handler|
          handler.on_completion do |response|
            typecheck_jobs_in_flight[worker] = typecheck_jobs_in_flight.fetch(worker, 0) - 1

            result = response[:result] #: CustomMethods::TypeCheck__File::result?
            on_type_check_update(
              guid: request.guid,
              path: path,
              target: target,
              source: result&.[](:source),
              signature: result&.[](:signature)
            )

            release_retired_workers()
            dispatch_typecheck_jobs()
          end
        end
      end

      def on_type_check_update(guid:, path:, target:, source: nil, signature: nil)
        if current = current_type_check_request()
          if current.guid == guid
            current.checked(path, target)

            if source
              type_check_database.update_source(
                path: path,
                target: target.name,
                diagnostics: source[:diagnostics],
                entries: source[:entries]&.map { TypeCheckDatabase::Entry.from_wire(_1) },
                stats: source[:stats]
              )
            end

            if signature
              type_check_database.update_signature(path: path, target: target.name, diagnostics: signature[:diagnostics])
            end

            source_diagnostics = source && source[:diagnostics]
            signature_diagnostics = signature && signature[:diagnostics]
            diagnostics =
              if source_diagnostics && signature_diagnostics
                source_diagnostics + signature_diagnostics
              else
                source_diagnostics || signature_diagnostics
              end

            Steep.logger.info { "Request updated: checked=#{path}, unchecked=#{current.each_unchecked_code_target_path.size}, diagnostics=#{diagnostics&.size}" }

            percentage = current.percentage
            current.work_done_progress.report(percentage, "#{current.checked_paths.size}/#{current.total}") if current.report_progress

            push_diagnostics(path, diagnostics)

            if current.finished?
              finish_type_check(current)
              @current_type_check_request = nil
              start_pending_typecheck()
            end
          end
        end
      end

      def broadcast_notification(message)
        Steep.logger.info "Broadcasting notification #{message[:method]}"
        each_worker do |worker|
          # The workers told to exit read nothing more
          next if exiting_workers.include?(worker)
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

      def group_request()
        GroupHandler.new().tap do |group|
          yield group

          if group.handlers.empty?
            # No response completes an empty group
            group.completion_handler&.call([])
          end
        end
      end

      def kill
        each_worker do |worker|
          worker.kill
        end
        launcher.stop
      end

      def enqueue_write_job(job)
        Steep.logger.info { "Write_queue has #{write_queue.size} items"}
        write_queue.push(job)
      end

      # Calls the block once no type check is running
      #
      # Starts a type check for dirty paths first, so that the block observes up-to-date results.
      #
      def run_when_typecheck_quiescent(&block)
        unless current_type_check_request
          guid = SecureRandom.uuid
          if request = controller.make_request(guid: guid, progress: work_done_progress(guid))
            request.needs_response = false
            start_type_check(request: request, last_request: nil)
          end
        end

        if current_type_check_request || !pending_typecheck_requests.empty?
          typecheck_quiescent_callbacks << block
        else
          yield
        end
      end

      # Starts the next queued type check request if any, or the automatic type check for dirty paths
      #
      # Calls the quiescent callbacks when nothing is left to type check.
      #
      def start_pending_typecheck
        while request = pending_typecheck_requests.shift
          start_type_check(request: request, last_request: nil)
          return if current_type_check_request
        end

        if typecheck_automatically && initialize_params
          guid = SecureRandom.uuid
          if request = controller.make_request(guid: guid, progress: work_done_progress(guid))
            request.needs_response = false
            start_type_check(request: request, last_request: nil)
            return if current_type_check_request
          end
        end

        flush_typecheck_quiescent_callbacks()
      end

      # Calls the waiting quiescent callbacks, once a type check for the paths that went dirty
      # in the meantime finishes
      #
      def flush_typecheck_quiescent_callbacks
        return if typecheck_quiescent_callbacks.empty?
        return if current_type_check_request

        guid = SecureRandom.uuid
        if request = controller.make_request(guid: guid, progress: work_done_progress(guid))
          request.needs_response = false
          start_type_check(request: request, last_request: nil)
          return if current_type_check_request
        end

        callbacks = typecheck_quiescent_callbacks.dup
        typecheck_quiescent_callbacks.clear
        callbacks.each(&:call)
      end

      # Collects the stored diagnostics from all typecheck workers and sends the response
      #
      # `paths` is an array of absolute path strings to filter the result, or `nil` to return everything.
      #
      def collect_query_diagnostics(id, paths)
        entries =
          if paths
            # Files the server has not type checked yet are reported with `diagnostics: nil`
            paths.map do |path|
              path = Pathname(path)
              diagnostics = type_check_database.checked?(path) ? type_check_database.diagnostics(path) : nil
              { uri: PathHelper.to_uri(path).to_s, diagnostics: diagnostics }
            end
          else
            type_check_database.paths.map do |path|
              { uri: PathHelper.to_uri(path).to_s, diagnostics: type_check_database.diagnostics(path) }
            end
          end #: CustomMethods::Query__Diagnostics::result

        entries.sort_by! { _1[:uri] }

        enqueue_write_job SendMessageJob.to_client(
          message: CustomMethods::Query__Diagnostics.response(id, entries)
        )
      end

      def update_environment
        changes = controller.pop_file_changes
        return if changes.empty?
        service = controller.type_check_service or return

        signature_files = signature_files_in(changes)
        updated_paths = controller.detect_declaration_changes()
        generation = nil #: Integer?

        case launcher
        when SpawnLauncher
          # The workers update their environments with the files by themselves
          broadcast_contents(signature_files.map { |_, path| path })
        when ForkLauncher
          if updated_paths.empty?
            # The workers keep their environments, and the master validates the RBS files they don't have
            signature_files.each do |_, path|
              signature_paths_to_validate << path if controller.files.signature_paths.registered_path?(path)
            end
          else
            # The next generation is forked from the environments updated with the declarations
            generation = (@environment_generation += 1)
            signature_paths_to_validate.clear
            launcher.retire_workers()
            release_retired_workers()
          end
        end

        environment_queue << -> do
          begin
            Steep.measure("Updating the environments with #{changes.size} files") do
              service.update(changes: changes)
            end
            index_signatures(service, signature_files)

            if generation && generation == @environment_generation
              warm_definitions(service)
            end
          ensure
            # Forks the generation of the latest update only, while the environments are not being updated. The workers
            # are forked even if the update fails, with the environments as they are.
            if generation && generation == @environment_generation
              forked = Thread::Queue.new

              job_queue << -> do
                fork_workers(service, generation)
              ensure
                forked << true
              end

              forked.pop
            end
          end
        rescue ClosedQueueError
          # The main loop has stopped
        end
      end

      def signature_files_in(changes)
        changes.each_key.filter_map do |relative_path|
          path = project.absolute_path(relative_path)
          if target = controller.files.signature_paths.target(path) || controller.files.inline_paths.target(path)
            [target.name, path]
          end
        end
      end

      def fork_workers(service, generation)
        launcher = self.launcher
        return unless launcher.is_a?(ForkLauncher)

        # No workers are forked after `shutdown`, and a newer update forks the workers again
        return if @shutting_down || job_queue.closed?
        return unless generation == @environment_generation

        Steep.measure("Forking the workers...") do
          launcher.start(service)
        end
        start_worker_threads()

        dispatch_typecheck_jobs()
      end

      def warm_definitions(service)
        Steep.measure("Building the definitions of the project") do
          project.targets.each do |target|
            signature_service = service.signature_services.fetch(target.name)
            subtyping = signature_service.current_subtyping or next
            builder = subtyping.factory.definition_builder
            env = builder.env

            signature_service.type_names(paths: Set.new(signature_service.files.each_key), env: env).each do |name|
              case
              when env.class_decls.key?(name)
                builder.build_instance(name)
                builder.build_singleton(name)
              when env.interface_decls.key?(name)
                builder.build_interface(name)
              end
            rescue RBS::BaseError
              # The validation reports the error
            end
          end
        end
      end

      def validate_signature_on_environment(request, target_name, path)
        service = controller.type_check_service or raise "The project is not loaded yet"
        target = project.targets.find {|target| target.name == target_name } or raise "Unknown target: #{target_name}"
        relative_path = project.relative_path(path)

        environment_queue << -> do
          diagnostics =
            begin
              formatter = Diagnostic::LSPFormatter.new({}, base_dir: project.base_dir)
              service.validate_signature(path: relative_path, target: target).filter_map { formatter.format(_1) }
            rescue => exn
              Steep.log_error(exn, message: "Failed to validate #{relative_path}: #{exn.inspect}")
              nil
            end

          job_queue << -> do
            on_type_check_update(guid: request.guid, path: path, target: target, signature: { diagnostics: diagnostics, entries: nil, stats: nil })
          end
        rescue ClosedQueueError
          # The main loop has stopped
        end
      end

      def release_retired_workers
        # The workers stop at `exit` after `shutdown`
        return if @shutting_down

        retiring_workers.each do |worker|
          next if typecheck_jobs_in_flight.fetch(worker, 0) > 0

          exiting_workers << worker
          @exited_wait_threads_mutex.synchronize { @exited_wait_threads << worker.wait_thread }
          send_notification({ method: "exit" }, worker: worker)
        end
      end

      def wire_content(text)
        if text.valid_encoding?
          text
        else
          { text: [text].pack("m"), binary: true }
        end
      end

      def broadcast_contents(paths)
        content = {} #: Hash[String, ChangeBuffer::content]

        paths.each do |path|
          relative_path = project.relative_path(path)
          if file = controller.file_contents.fetch(relative_path, nil)
            content[relative_path.to_s] = wire_content(file.text)
          end
        end

        return if content.empty?

        Steep.logger.info { "Sending the contents of #{content.size} files to the workers" }
        typecheck_workers.each do |worker|
          enqueue_write_job SendMessageJob.to_worker(worker, message: CustomMethods::FileLoad.notification({ content: content }))
        end
      end

      def run_interaction(message, interaction, &block)
        service = controller.type_check_service
        path = pathname(message[:params][:textDocument][:uri])
        position = message[:params][:position] #: InteractionProvider::position?

        if path.nil? || position.nil? || service.nil?
          block[nil]
          return
        end

        line = position[:line] + 1
        column = position[:character]

        # The interaction sees the changes received so far, which the environment thread applies first
        update_environment()

        count = (@interaction_count += 1)
        provider = InteractionProvider.new(service: service)

        environment_queue << -> do
          result =
            if count == @interaction_count
              begin
                interaction[provider, path, line, column]
              rescue => exn
                Steep.log_error(exn, message: "Failed to answer the interaction request: #{exn.inspect}")
                nil
              end
            else
              Steep.logger.info { "Skipping the interaction request: a newer one is waiting" }
              nil
            end

          block[result]
        rescue ClosedQueueError
          # The main loop has stopped
        end
      end

      def respond_to_interaction(message, result)
        id = message[:id]
        service = controller.type_check_service

        # Renders on the environment thread, with the environments the interaction ran with
        lsp_result =
          if result && service
            begin
              case message[:method]
              when "textDocument/hover"
                hover = result #: InteractionProvider::Hover::result
                LSPFormatter.hover(hover, service: service)
              when "textDocument/completion"
                completion = result #: InteractionProvider::Completion::result
                LSPFormatter.completion_list(completion, service: service)
              when "textDocument/signatureHelp"
                signature_help = result #: InteractionProvider::SignatureHelp::result
                if signature_help[:syntax_error]
                  # The file cannot be parsed while the user types: keep the signature help the client is showing, if any
                  message[:params].dig(:context, :activeSignatureHelp)
                elsif help = signature_help[:signature_help]
                  LSPFormatter.signature_help(help, service: service)
                end
              end
            rescue => exn
              Steep.log_error(exn, message: "Failed to format the result of #{message[:method]}: #{exn.inspect}")
              nil
            end
          end

        enqueue_write_job SendMessageJob.to_client(message: { id: id, result: lsp_result })
      end

      def workspace_symbol_result(query)
        Steep.measure "Generating workspace symbol list for query=`#{query}`" do
          uris = {} #: Hash[Pathname, String]

          names = type_check_database.matching_names(query)

          symbols = type_check_database.rbs_definitions(names).map do |definition|
            name, container_name = workspace_symbol_name(definition.name, definition.kind)
            location = definition.location

            LSP::Interface::SymbolInformation.new(
              name: name,
              kind: WORKSPACE_SYMBOL_KINDS.fetch(definition.kind),
              location: {
                uri: uris[location.path] ||= PathHelper.to_uri(location.path).to_s,
                range: location.lsp_range
              },
              container_name: container_name
            )
          end

          symbols.sort_by!(&:name)
        end
      end

      def workspace_symbol_name(name, kind)
        case kind
        when :method, :attribute
          # `::Foo::Bar#baz` is `#baz` in `Foo::Bar`, and `::Foo::Bar.baz` is `.baz` in `Foo::Bar`
          index = name.index(/[#.]/) or raise "Unexpected method name: #{name}"
          [name[index..] || raise, name[0, index]&.delete_prefix("::")]
        when :global
          [name, nil]
        else
          # `::Foo::Bar` is `Bar` in `Foo`, and `::Foo` is `Foo` in `""`
          namespace, _, base = name.delete_prefix("::").rpartition("::")
          [base, namespace]
        end
      end

      def stats_result
        targets = project.targets.each.with_object({}) do |target, hash| #$ Hash[Symbol, Project::Target]
          hash[target.name] = target
        end

        stats = [] #: Array[Services::StatsCalculator::json_stats]

        type_check_database.each_source do |path, result|
          target = targets.fetch(result.target, nil) or next
          relative_path = project.relative_path(path)

          stats <<
            if calls = result.stats
              Services::StatsCalculator::SuccessStats.new(
                target: target,
                path: relative_path,
                typed_calls_count: calls[:typed_calls],
                untyped_calls_count: calls[:untyped_calls],
                error_calls_count: calls[:error_calls]
              ).as_json
            else
              Services::StatsCalculator::ErrorStats.new(target: target, path: relative_path).as_json
            end
        end

        stats.sort_by! { _1[:path] }
      end

      # Methods that command socket clients cannot send because they control the server lifecycle
      # The only methods a command socket client may send: what `steep check` and
      # `steep query` use. Everything else is rejected -- lifecycle methods because the
      # server belongs to whoever started it, and document synchronization because the
      # LSP client owns the content of the files it opens.
      COMMAND_SOCKET_ALLOWED_METHODS = [
        CustomMethods::TypeCheck::METHOD,
        CustomMethods::Query__Diagnostics::METHOD,
        CustomMethods::Query__Definition::METHOD,
        "textDocument/hover",
        "$/ping"
      ].freeze

      # Notifications that are copied to command socket sessions with a pending `$/steep/typecheck` request
      COMMAND_SOCKET_FORWARDED_NOTIFICATIONS = ["textDocument/publishDiagnostics", "window/showMessage"].freeze

      # Processes a message received from a command socket client
      #
      # Requests are assigned a fresh id and enqueued as if they came from the LSP client,
      # and the responses are routed back to the session through `#write_message_to_client`.
      #
      # May be called from any thread.
      #
      def process_command_socket_message(message, session)
        method = message[:method]
        id = message[:id]

        if method && !COMMAND_SOCKET_ALLOWED_METHODS.include?(method.to_s)
          Steep.logger.warn { "Command socket: rejected `#{method}`" }
          if id
            session.write({
              id: id,
              error: {
                code: LSP::Constant::ErrorCodes::INVALID_REQUEST,
                message: "`#{method}` is not allowed through the command socket"
              }
            })
          end
          return
        end

        unless initialize_params
          if id
            session.write({
              id: id,
              error: {
                code: LSP::Constant::ErrorCodes::SERVER_NOT_INITIALIZED,
                message: "The language server is not initialized yet"
              }
            })
          end
          return
        end

        case
        when method && id
          guid = SecureRandom.uuid
          @command_socket_mutex.synchronize do
            @command_socket_requests[guid] = [session, id, method.to_s == CustomMethods::TypeCheck::METHOD]
          end
          message = message.merge({ id: guid })
        when id
          # A response from the client, but nothing is waiting for it
          return
        end

        # Reload files changed on disk before processing, because command socket clients
        # modify files without sending `didChange` notifications
        job_queue << -> do
          sync_project_files_from_disk()
          process_message_from_client(message)
        end
      rescue ClosedQueueError
        Steep.logger.warn { "Command socket: server is shutting down" }
      end

      # Deregisters the pending requests of a disconnected command socket session
      def finish_command_socket_session(session)
        @command_socket_mutex.synchronize do
          @command_socket_requests.delete_if {|_, entry| entry[0] == session }
        end
      end

      def write_message_to_client(message)
        unless message.key?(:method)
          entry = @command_socket_mutex.synchronize { @command_socket_requests.delete(message[:id]) }
          if entry
            session, original_id, _ = entry
            session.write(message.merge({ id: original_id }))
            return
          end
        end

        writer.write(message)

        if message.key?(:method) && !message.key?(:id)
          forward_notification_to_command_sessions(message)
        end
      end

      def forward_notification_to_command_sessions(message)
        return unless COMMAND_SOCKET_FORWARDED_NOTIFICATIONS.include?(message[:method].to_s)

        sessions = @command_socket_mutex.synchronize do
          @command_socket_requests.each_value.with_object([]) do |entry, array|
            session, _, typecheck = entry
            array << session if typecheck
          end
        end

        sessions.uniq!
        sessions.each {|session| session.write(message) }
      end

      def typecheck_request_from_command_socket?(request)
        @command_socket_mutex.synchronize do
          @command_socket_requests.key?(request.guid)
        end
      end

      # Records the mtimes of all project files, as the baseline of `#sync_project_files_from_disk`
      def reset_project_file_mtimes
        mtimes = {} #: Hash[Pathname, Time?]
        each_project_file_path do |path|
          mtimes[path] = file_mtime(path)
        end
        @project_file_mtimes = mtimes
      end

      def record_project_file_mtime(path)
        if mtimes = @project_file_mtimes
          mtimes[path] = file_mtime(path)
        end
      end

      def file_mtime(path)
        File.mtime(path)
      rescue SystemCallError
        nil
      end

      def each_project_file_path(&block)
        loader = Services::FileLoader.new(base_dir: project.base_dir)
        project.targets.each do |target|
          loader.each_path_in_target(target) do |relative_path|
            yield project.absolute_path(relative_path)
          end
        end
      end

      # Detects files changed on disk since the last load/sync, and reloads them
      #
      # Skips files open in the editor because the client owns their contents.
      # Does nothing until the initial project load finishes.
      #
      def sync_project_files_from_disk
        mtimes = @project_file_mtimes or return

        changes = {} #: Hash[Pathname, Symbol]
        seen = Set[] #: Set[Pathname]

        each_project_file_path do |path|
          next if seen.include?(path)
          seen << path

          mtime = file_mtime(path)
          recorded = mtimes[path]

          case
          when recorded.nil? && mtime
            changes[path] = mtimes.key?(path) ? :changed : :created
          when recorded && mtime.nil?
            changes[path] = :deleted
          when recorded != mtime
            changes[path] = :changed
          end

          mtimes[path] = mtime
        end

        deleted_paths = mtimes.keys.select {|path| !seen.include?(path) && mtimes[path] && file_mtime(path).nil? }
        deleted_paths.each do |path|
          changes[path] = :deleted
          mtimes[path] = nil
        end

        changes.delete_if {|path, _| controller.open_paths.include?(path) }
        return if changes.empty?

        Steep.logger.info { "Command socket: reloading #{changes.size} file(s) changed on disk" }

        changes.each do |path, type|
          content =
            if type == :deleted
              ""
            else
              begin
                path.read
              rescue SystemCallError
                next
              end
            end

          case
          when controller.code_path?(path)
            controller.add_dirty_code_path(path, content)
          when controller.signature_path?(path)
            controller.add_dirty_signature_path(path, content)
          when controller.inline_path?(path)
            controller.add_dirty_inline_path(path, content)
          end
        end

        if typecheck_automatically
          start_type_checking_queue.execute do
            job_queue.push(
              -> do
                start_type_check(
                  last_request: current_type_check_request,
                  progress: work_done_progress(SecureRandom.uuid),
                  needs_response: false
                )
              end
            )
          end
        end
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
          unless related_information_supported?
            diagnostics = diagnostics.map { _1.except(:relatedInformation) }
          end

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
