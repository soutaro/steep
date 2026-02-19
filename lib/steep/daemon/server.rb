# frozen_string_literal: true

module Steep
  module Daemon
    class Server
      attr_reader :config, :project, :stderr
      attr_reader :file_tracker, :shutdown_flag
      attr_reader :warmup_status, :warmup_mutex

      # LSP file change types (from Language Server Protocol specification)
      FILE_CHANGE_TYPE = {
        created: 1,
        changed: 2,
        deleted: 3
      }.freeze

      class FileTracker
        def initialize
          @mtimes = {}
          @pending_changes = {}
          @mutex = Mutex.new
        end

        def register(paths)
          @mutex.synchronize do
            paths.each do |path|
              key = path.to_s
              @mtimes[key] ||= safe_mtime(key)
            end
          end
        end

        def record_changes(changes)
          @mutex.synchronize do
            changes.each do |path, type|
              @pending_changes[path] = type
            end
          end
        end

        def flush_pending_changes
          @mutex.synchronize do
            changes = @pending_changes.to_a
            @pending_changes.clear

            changes.each do |path, type|
              @mtimes[path] = type == :deleted ? nil : safe_mtime(path)
            end

            changes
          end
        end

        def track_and_detect(paths)
          @mutex.synchronize do
            changed = [] #: Array[[String, Symbol]]
            paths.each do |path|
              key = path.to_s
              current = safe_mtime(key)
              old = @mtimes[key]

              if old.nil?
                @mtimes[key] = current
                changed << [key, :created] if current
              elsif current != old
                @mtimes[key] = current
                type = current ? :changed : :deleted
                changed << [key, type]
              end
            end
            changed
          end
        end

        private

        def safe_mtime(path)
          File.mtime(path)
        rescue Errno::ENOENT
          nil
        end
      end

      def initialize(config:, project:, stderr:)
        @config = config
        @project = project
        @stderr = stderr
        @shutdown_flag = false
        @file_tracker = FileTracker.new
        @warmup_status = :not_started  # :warming_up, :ready, :failed
        @warmup_mutex = Mutex.new
      end

      def run
        Steep.logger.info { "Steep server starting for #{Dir.pwd}" }
        Steep.logger.info { "PID: #{Process.pid}" }

        client_read, server_write = IO.pipe
        server_read, client_write = IO.pipe

        client_reader = LanguageServer::Protocol::Transport::Io::Reader.new(client_read)
        client_writer = LanguageServer::Protocol::Transport::Io::Writer.new(client_write)
        server_reader = LanguageServer::Protocol::Transport::Io::Reader.new(server_read)
        server_writer = LanguageServer::Protocol::Transport::Io::Writer.new(server_write)

        job_count = (ENV["STEEP_SERVER_JOB_COUNT"] || [Etc.nprocessors - 1, 1].max).to_i

        Steep.logger.info { "Starting #{job_count} typecheck worker(s)..." }

        workers = ::Steep::Server::WorkerProcess.start_typecheck_workers(
          steepfile: @project.steepfile_path,
          args: [],
          delay_shutdown: true,
          steep_command: nil,
          count: job_count
        )

        master = ::Steep::Server::Master.new(
          project: @project,
          reader: server_reader,
          writer: server_writer,
          interaction_worker: nil,
          typecheck_workers: workers,
          refork: true
        )
        master.typecheck_automatically = false

        master_thread = Thread.start do
          Thread.current.abort_on_exception = true
          master.start
        end

        Steep.logger.info { "Initializing (loading RBS environment)..." }
        init_id = SecureRandom.alphanumeric(10)
        client_writer.write(method: :initialize, id: init_id, params: {})
        wait_for_response(client_reader, init_id)

        all_paths = collect_all_project_paths
        @file_tracker.register(all_paths)

        Steep.logger.info { "Server ready. Tracking #{all_paths.size} files." }
        Steep.logger.info { "Socket: #{@config.socket_path}" }

        # SAFE: Verify socket path is actually a socket before deleting (prevents symlink attacks)
        if File.exist?(@config.socket_path)
          unless File.socket?(@config.socket_path)
            raise "#{@config.socket_path} exists but is not a socket (possible symlink attack)"
          end
          File.delete(@config.socket_path)
        end
        @unix_server = UNIXServer.new(@config.socket_path)
        # SAFE: Restrict socket access to owner only (prevents unauthorized connections)
        File.chmod(0600, @config.socket_path)

        warmup_thread = Thread.new do
          Thread.current.abort_on_exception = false
          set_warmup_status(:warming_up)
          stderr.puts "Warming up type checker (loading gem signatures and RBS files)..."
          warm_typecheck_on_startup(client_writer, client_reader)
          stderr.puts "Warm-up complete. Ready for fast type checking."
          set_warmup_status(:ready)
        rescue StandardError => e
          Steep.logger.error { "Warm-up error: #{e.class}: #{e.message}" }
          Steep.logger.debug { e.backtrace.first(10).join("\n") }
          set_warmup_status(:failed)
        end

        watcher_thread = start_background_watcher(client_writer, client_reader)

        server = @unix_server or raise

        Signal.trap("TERM") { @shutdown_flag = true; server.close rescue nil }
        Signal.trap("INT")  { @shutdown_flag = true; server.close rescue nil }

        until @shutdown_flag
          begin
            ready = IO.select([server], nil, nil, 1) # steep:ignore UnresolvedOverloading
            next unless ready

            client_socket = server.accept

            unless warmup_ready?
              sleep 0.1 until warmup_ready? || @shutdown_flag
            end

            next if @shutdown_flag

            handle_client(client_socket, client_writer, client_reader)
          rescue IOError, Errno::EBADF
            break if @shutdown_flag
            raise
          rescue StandardError => e
            Steep.logger.error { "Error handling client: #{e.class}: #{e.message}" }
            Steep.logger.debug { e.backtrace.first(10).join("\n") }
          ensure
            client_socket&.close rescue nil
          end
        end

        Steep.logger.info { "Shutting down..." }
        warmup_thread&.kill
        watcher_thread&.kill
        shutdown_master(client_writer, client_reader)
        master_thread.join(10)
      rescue StandardError => e
        Steep.logger.fatal { "Fatal error: #{e.class}: #{e.message}" }
        Steep.logger.error { e.backtrace.join("\n") }
      ensure
        Daemon.cleanup
        Steep.logger.info { "Server stopped." }
      end

      private

      def warmup_ready?
        @warmup_mutex.synchronize { @warmup_status == :ready }
      end

      def set_warmup_status(status)
        @warmup_mutex.synchronize { @warmup_status = status }
      end

      def handle_client(client_socket, master_writer, master_reader)
        client_reader = LanguageServer::Protocol::Transport::Io::Reader.new(client_socket)
        client_writer = LanguageServer::Protocol::Transport::Io::Writer.new(client_socket)

        request = read_one_message(client_reader) or return

        client_request_id = request[:id]
        params = request[:params]

        code_count = params[:code_paths]&.size || 0
        sig_count  = params[:signature_paths]&.size || 0
        Steep.logger.info { "Check request: #{code_count} code, #{sig_count} signature files" }

        sync_changed_files(master_writer, params)

        request_guid = SecureRandom.uuid
        master_writer.write(
          ::Steep::Server::CustomMethods::TypeCheck.request(request_guid, params)
        )

        master_reader.read do |message|
          if message[:id] == request_guid
            client_writer.write({ id: client_request_id, result: message[:result] })
            return
          end

          client_writer.write(message)
        end
      rescue Errno::EPIPE, IOError
        Steep.logger.warn { "Client disconnected during check" }
      end

      def sync_changed_files(master_writer, params)
        request_paths = [] #: Array[String]
        (params[:code_paths] || []).each { |_, path| request_paths << path }
        (params[:signature_paths] || []).each { |_, path| request_paths << path }

        changes_map = {} #: Hash[String, Symbol]
        @file_tracker.flush_pending_changes.each { |path, type| changes_map[path] = type }
        @file_tracker.track_and_detect(request_paths).each { |path, type| changes_map[path] = type }

        return if changes_map.empty?

        Steep.logger.info { "Syncing #{changes_map.size} changed file(s) to workers" }

        lsp_changes = changes_map.map do |path, type|
          { uri: "file://#{path}", type: FILE_CHANGE_TYPE[type] }
        end

        master_writer.write(
          method: "workspace/didChangeWatchedFiles",
          params: { changes: lsp_changes }
        )
      end

      def collect_all_project_paths
        paths = Set.new
        loader = ::Steep::Services::FileLoader.new(base_dir: @project.base_dir)

        @project.targets.each do |target|
          loader.each_path_in_target(target) do |path|
            abs = @project.absolute_path(path)
            paths << abs.to_s if abs.file?
          end
        end

        sig_dir = @project.base_dir + "sig"
        if sig_dir.directory?
          sig_dir.glob("**/*.rbs").each { |p| paths << p.to_s if p.file? }
        end

        paths.to_a
      end

      def start_background_watcher(master_writer, master_reader)
        require "listen"

        watch_dirs = [@project.base_dir.to_s]

        listener = Listen.to(*watch_dirs, only: /\.(rb|rbs)$/, wait_for_delay: 1) do |modified, added, removed|
          all_paths = modified + added + removed
          next if all_paths.empty?

          changes = build_lsp_changes(all_paths, added, removed)
          next if changes.empty?

          has_signature_change = all_paths.any? { |p| p.end_with?(".rbs") }

          Steep.logger.info { "Watcher: #{changes.size} file(s) changed" +
                              (has_signature_change ? " (includes signatures, pre-warming...)" : "") }

          master_writer.write(
            method: "workspace/didChangeWatchedFiles",
            params: { changes: changes }
          )

          if has_signature_change
            warm_typecheck(master_writer, master_reader)
          end
        rescue StandardError => e
          Steep.logger.error { "Watcher error: #{e.class}: #{e.message}" }
          Steep.logger.debug { e.backtrace.first(5).join("\n") }
        end

        Thread.new do
          listener.start
          sleep
        rescue StandardError => e
          Steep.logger.error { "Watcher thread error: #{e.class}: #{e.message}" }
        end
      end

      def categorize_path_changes(all_paths, added, removed)
        added_set = added.to_set
        removed_set = removed.to_set

        all_paths.map do |path|
          if added_set.include?(path)
            :created
          elsif removed_set.include?(path)
            :deleted
          else
            :changed
          end
        end
      end

      def build_lsp_changes(all_paths, added, removed)
        types = categorize_path_changes(all_paths, added, removed)

        all_paths.zip(types).map do |path, type|
          { uri: "file://#{path}", type: FILE_CHANGE_TYPE[type || :changed] }
        end
      end

      def collect_warmup_files
        params = { library_paths: [], inline_paths: [], signature_paths: [], code_paths: [] } #: ::Steep::Server::CustomMethods::TypeCheck::params
        loader = ::Steep::Services::FileLoader.new(base_dir: @project.base_dir)

        @project.targets.each do |target|
          loader.each_path_in_target(target) do |path|
            abs = @project.absolute_path(path)
            if abs.file? && abs.to_s.end_with?(".rb")
              params[:code_paths] << [target.name.to_s, abs.to_s]
              break
            end
          end
        end

        params
      end

      def warm_typecheck(master_writer, master_reader)
        params = collect_warmup_files
        return if params[:code_paths].empty?

        guid = SecureRandom.uuid
        Steep.logger.info { "Watcher: warm-up typecheck started (#{params[:code_paths].size} targets)" }
        master_writer.write(
          ::Steep::Server::CustomMethods::TypeCheck.request(guid, params)
        )

        master_reader.read do |message|
          if message[:id] == guid
            Steep.logger.info { "Watcher: warm-up typecheck completed" }
            break
          end
        end
      end

      def warm_typecheck_on_startup(master_writer, master_reader)
        params = collect_warmup_files

        if params[:code_paths].empty?
          Steep.logger.warn { "No Ruby files found for warm-up, skipping" }
          return
        end

        guid = SecureRandom.uuid
        Steep.logger.info { "Checking #{params[:code_paths].size} file(s) to trigger RBS loading..." }

        start_time = Time.now
        master_writer.write(
          ::Steep::Server::CustomMethods::TypeCheck.request(guid, params)
        )

        master_reader.read do |message|
          if message[:id] == guid
            elapsed = Time.now - start_time
            Steep.logger.info { "RBS environment loaded in #{elapsed.round(2)}s" }
            break
          end
        end
      end

      def wait_for_response(reader, id)
        reader.read do |message|
          return message if message[:id] == id
        end
      end

      def read_one_message(reader)
        reader.read do |message|
          return message
        end
      end

      def shutdown_master(writer, reader)
        id = SecureRandom.alphanumeric(10)
        writer.write(method: :shutdown, id: id)
        wait_for_response(reader, id)
        writer.write(method: :exit)
      rescue StandardError => e
        Steep.logger.error { "Shutdown error: #{e.message}" }
      end
    end
  end
end
