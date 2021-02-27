module Steep
  module Server
    class SignatureWorker < BaseWorker
      attr_reader :queue
      attr_reader :controllers

      def initialize(project:, reader:, writer:, queue: Queue.new)
        super(project: project, reader: reader, writer: writer)

        @queue = queue
        @changes = {}
        @mutex = Mutex.new
        @controllers = project.targets.each.with_object({}) do |target, hash|
          loader = Project::Target.construct_env_loader(options: target.options)
          hash[target.name] = SignatureController.load_from(loader)
        end
      end

      def push_change
        @mutex.synchronize do
          yield @changes
        end
      end

      def pop_change
        changes = {}
        @mutex.synchronize do
          changes.merge!(@changes)
          @changes.clear
        end
        if block_given?
          yield changes
        else
          changes
        end
      end

      def enqueue_validation()
        queue << [:validate, []]
      end

      def enqueue_symbol(id:, query:)
        Steep.logger.info "Queueing symbol #{query} (#{id})"
        queue << [:symbol, [id, query]]
      end

      def load_project_files()
        push_change do |changes|
          project.targets.each do |target|
            target_changes = target.signature_files.each.with_object({}) do |(path, file), hash|
              changes[path] = [Services::ContentChange.new(text: file.content)]
            end
          end
        end
      end

      def handle_request(request)
        case request[:method]
        when "initialize"
          load_project_files()
          enqueue_validation()
          writer.write({ id: request[:id], result: nil})

        when "textDocument/didChange"
          collect_changes(request)
          enqueue_validation()

        when "workspace/symbol"
          enqueue_symbol(query: request[:params][:query], id: request[:id])
        end
      end

      def collect_changes(request)
        push_change do |changes|
          path = project.relative_path(Pathname(URI.parse(request[:params][:textDocument][:uri]).path))
          version = request[:params][:textDocument][:version]
          Steep.logger.info { "Updating source: path=#{path}, version=#{version}..." }

          changes[path] ||= []
          request[:params][:contentChanges].each do |change|
            changes[path] << Services::ContentChange.new(
              range: change[:range]&.yield_self {|range|
                [
                  range[:start].yield_self {|pos| Services::ContentChange::Position.new(line: pos[:line] + 1, column: pos[:character]) },
                  range[:end].yield_self {|pos| Services::ContentChange::Position.new(line: pos[:line] + 1, column: pos[:character]) }
                ]
              },
              text: change[:text]
            )
          end
        end
      end

      def validate_signature(changes:)
        Steep.logger.info { "#validate_signature: changes=#{changes.keys.join(", ")}"}
        all_diagnostics = {}

        project.targets.each do |target|
          controller = controllers[target.name]
          target_changes = changes.filter {|path, _| target.possible_signature_file?(path) }

          if !target_changes.empty?
            controller.update(target_changes) unless target_changes.empty?

            diagnostics = case controller.status
                          when SignatureController::ErrorStatus
                            controller.status.diagnostics
                          when SignatureController::LoadedStatus
                            check = Subtyping::Check.new(factory: AST::Types::Factory.new(builder: controller.current_builder))
                            Signature::Validator.new(checker: check).tap {|v| v.validate() }.each_error.to_a
                          end.group_by {|error| error.location.buffer.name }

            formatter = Diagnostic::LSPFormatter.new
            controller.current_files.each_key do |path|
              all_diagnostics[path] ||= []
              all_diagnostics[path].push(*(diagnostics[path] || []).map {|error| formatter.format(error) })
            end
          end
        end

        all_diagnostics.each do |path, diagnostics|
          Steep.logger.info { "Reporting #{diagnostics.size} diagnostics for #{path}" }
          writer.write(
            method: :"textDocument/publishDiagnostics",
            params: LSP::Interface::PublishDiagnosticsParams.new(
              uri: URI.parse(project.absolute_path(path).to_s).tap {|uri| uri.scheme = "file"},
              diagnostics: diagnostics.uniq
            )
          )
        end
      end

      def handle_workspace_symbol(query:, id:)
        provider = Index::SignatureSymbolProvider.new()

        project.targets.each do |target|
          controller = controllers[target.name]

          index = Index::RBSIndex.new()

          builder = Index::RBSIndex::Builder.new(index: index)
          builder.env(controller.current_env)

          provider.indexes << index
        end

        symbols = provider.query_symbol(query)

        result = symbols.map do |symbol|
          {
            name: symbol.name.to_s,
            kind: symbol.kind,
            deprecated: false,
            containerName: symbol.container_name.to_s,
            location: {
              uri: URI.parse(project.absolute_path(symbol.location.buffer.name).to_s),
              range: {
                start: LSP::Interface::Position.new(
                  line: symbol.location.start_line - 1,
                  character: symbol.location.start_column,
                  ),
                end: LSP::Interface::Position.new(
                  line: symbol.location.end_line - 1,
                  character: symbol.location.end_column
                )
              }
            }
          }
        end

        writer.write(id: id, result: result)
      end

      def handle_job(job)
        Steep.logger.info { "#handle_job: #{job.inspect}"}
        action, data = job

        case action
        when :validate
          changes = pop_change()
          Steep.measure "Signature validation", level: :info do
            validate_signature(changes: changes)
          end

        when :symbol
          id, query = data
          Steep.measure "Symbol list generation", level: :info do
            handle_workspace_symbol(query: query, id: id)
          end
        end
      end
    end
  end
end
