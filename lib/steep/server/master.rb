module Steep
  module Server
    class Master
      LSP = LanguageServer::Protocol

      attr_reader :steepfile
      attr_reader :project
      attr_reader :reader, :writer
      attr_reader :queue
      attr_reader :worker_count
      attr_reader :worker_to_paths

      attr_reader :interaction_worker
      attr_reader :signature_worker
      attr_reader :code_workers

      def initialize(project:, reader:, writer:, interaction_worker:, signature_worker:, code_workers:, queue: Queue.new)
        @project = project
        @reader = reader
        @writer = writer
        @queue = queue
        @interaction_worker = interaction_worker
        @signature_worker = signature_worker
        @code_workers = code_workers
        @worker_to_paths = {}
        @shutdown_request_id = nil
      end

      def start
        source_paths = project.targets.flat_map {|target| target.source_files.keys }
        bin_size = (source_paths.size / code_workers.size) + 1
        source_paths.each_slice(bin_size).with_index do |paths, index|
          register_code_to_worker(paths, worker: code_workers[index])
        end

        Thread.new do
          interaction_worker.reader.read do |message|
            process_message_from_worker(message)
          end
        end

        Thread.new do
          signature_worker.reader.read do |message|
            process_message_from_worker(message)
          end
        end

        code_workers.each do |worker|
          Thread.new do
            worker.reader.read do |message|
              process_message_from_worker(message)
            end
          end
        end

        Thread.new do
          reader.read do |request|
            process_message_from_client(request)
          end
        end

        while job = queue.pop
          if @shutdown_request_id
            if job[:id] == @shutdown_request_id
              writer.write(job)
              break
            end
          else
            writer.write(job)
          end
        end

        writer.io.close

        each_worker do |w|
          w.shutdown()
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
        id = message[:id]

        case message[:method]
        when "initialize"
          queue << {
            id: id,
            result: LSP::Interface::InitializeResult.new(
              capabilities: LSP::Interface::ServerCapabilities.new(
                text_document_sync: LSP::Interface::TextDocumentSyncOptions.new(
                  change: LSP::Constant::TextDocumentSyncKind::FULL
                ),
                hover_provider: true,
                completion_provider: LSP::Interface::CompletionOptions.new(
                  trigger_characters: [".", "@"]
                )
              )
            )
          }

          each_worker do |worker|
            worker << message
          end

        when "textDocument/didChange"
          uri = URI.parse(message[:params][:textDocument][:uri])
          path = project.relative_path(Pathname(uri.path))
          text = message[:params][:contentChanges][0][:text]

          project.targets.each do |target|
            case
            when target.source_file?(path)
              if text.empty? && !path.file?
                Steep.logger.info { "Deleting source file: #{path}..." }
                target.remove_source(path)
              else
                Steep.logger.info { "Updating source file: #{path}..." }
                target.update_source(path, text)
              end
            when target.possible_source_file?(path)
              Steep.logger.info { "Adding source file: #{path}..." }
              target.add_source(path, text)
            when target.signature_file?(path)
              if text.empty? && !path.file?
                Steep.logger.info { "Deleting signature file: #{path}..." }
                target.remove_signature(path)
              else
                Steep.logger.info { "Updating signature file: #{path}..." }
                target.update_signature(path, text)
              end
            when target.possible_signature_file?(path)
              Steep.logger.info { "Adding signature file: #{path}..." }
              target.add_signature(path, text)
            end
          end

          unless registered_path?(path)
            register_code_to_worker [path], worker: least_busy_worker()
          end

          each_worker do |worker|
            worker << message
          end

        when "textDocument/hover"
          interaction_worker << message

        when "textDocument/completion"
          interaction_worker << message

        when "textDocument/open"
          # Ignores open notification

        when "shutdown"
          queue << { id: id, result: nil }
          @shutdown_request_id = id

        when "exit"
          queue << nil
        end
      end

      def process_message_from_worker(message)
        queue << message
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

        worker << {
          method: "workspace/executeCommand",
          params: LSP::Interface::ExecuteCommandParams.new(
            command: "steep/registerSourceToWorker",
            arguments: paths.map do |path|
              "file://#{project.absolute_path(path)}"
            end
          )
        }
      end
    end
  end
end
