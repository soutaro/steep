module Steep
  module Server
    class TypeCheckWorker < BaseWorker
      attr_reader :project, :assignment, :service
      attr_reader :commandline_args

      TypeCheckJob = Struct.new(:request_id, :guid, :priority_paths, :library_paths, :signature_paths, :code_paths, keyword_init: true)
      WorkspaceSymbolJob = Struct.new(:query, :id, keyword_init: true)
      StatsJob = Struct.new(:id, keyword_init: true)

      include ChangeBuffer

      def initialize(project:, reader:, writer:, assignment:, commandline_args:)
        super(project: project, reader: reader, writer: writer)

        @assignment = assignment
        @service = Services::TypeCheckService.new(project: project)
        @buffered_changes = {}
        @mutex = Mutex.new()
        @queue = Queue.new
        @commandline_args = commandline_args
      end

      def handle_request(request)
        case request[:method]
        when "initialize"
          load_files(project: project, commandline_args: commandline_args)
          writer.write({ id: request[:id], result: nil})
        when "textDocument/didChange"
          collect_changes(request)
        when "workspace/symbol"
          query = request[:params][:query]
          queue << WorkspaceSymbolJob.new(id: request[:id], query: query)
        when "workspace/executeCommand"
          case request[:params][:command]
          when "steep/stats"
            queue << StatsJob.new(id: request[:id])
          end
        when "$/typecheck/start"
          params = request[:params]
          queue << TypeCheckJob.new(
            request_id: request[:id],
            guid: params[:guid],
            priority_paths: Set.new(params[:priority_uris].map {|uri| Pathname(URI.parse(uri).path) }),
            library_paths: params[:library_uris].map {|uri| Pathname(URI.parse(uri).path) },
            signature_paths: params[:signature_uris].map {|uri| Pathname(URI.parse(uri).path) },
            code_paths: params[:code_uris].map {|uri| Pathname(URI.parse(uri).path) }
          )
        end
      end

      def handle_job(job)
        case job
        when TypeCheckJob
          run_typecheck(job) do |path, diagnostics|
            absolute_path = project.absolute_path(path)

            if target = project.target_for_source_path(path)
              diagnostics = diagnostics.select {|diagnostic| target.options.error_to_report?(diagnostic) }
            end

            formatter = Diagnostic::LSPFormatter.new()

            writer.write(
              method: :"textDocument/publishDiagnostics",
              params: LSP::Interface::PublishDiagnosticsParams.new(
                uri: URI.parse(absolute_path.to_s).tap {|uri| uri.scheme = "file"},
                diagnostics: diagnostics.map {|diagnostic| formatter.format(diagnostic) }.uniq
              )
            )

            writer.write(
              method: "$/typecheck/progress",
              params: { guid: job.guid, path: absolute_path }
            )
          end
        when WorkspaceSymbolJob
          writer.write(
            id: job.id,
            result: workspace_symbol_result(job.query)
          )
        when StatsJob
          writer.write(
            id: job.id,
            result: stats_result().map(&:as_json)
          )
        end
      end

      def run_typecheck(job, &block)
        pop_buffer() do |changes|
          formatter = Diagnostic::LSPFormatter.new()

          request = service.update(changes: changes)

          job.library_paths.each do |path|
            if job.priority_paths.include?(path)
              service.validate_signature(path: path, &block)
            end
          end

          job.code_paths.each do |path|
            if job.priority_paths.include?(path)
              service.typecheck_source(
                path: project.relative_path(path),
                &block
              )
            end
          end

          job.signature_paths.each do |path|
            if job.priority_paths.include?(path)
              service.validate_signature(
                path: project.relative_path(path),
                &block
              )
            end
          end

          job.library_paths.each do |path|
            unless job.priority_paths.include?(path)
              service.validate_signature(path: path, &block)
            end
          end

          job.code_paths.each do |path|
            unless job.priority_paths.include?(path)
              service.typecheck_source(
                path: project.relative_path(path),
                &block
              )
            end
          end

          job.signature_paths.each do |path|
            unless job.priority_paths.include?(path)
              service.validate_signature(
                path: project.relative_path(path),
                &block
              )
            end
          end
        end
      end

      def workspace_symbol_result(query)
        Steep.measure "Generating workspace symbol list for query=`#{query}`" do
          indexes = project.targets.map {|target| service.signature_services[target.name].latest_rbs_index }

          provider = Index::SignatureSymbolProvider.new()
          provider.indexes.push(*indexes)

          symbols = provider.query_symbol(query, assignment: assignment)

          symbols.map do |symbol|
            LSP::Interface::SymbolInformation.new(
              name: symbol.name,
              kind: symbol.kind,
              location: symbol.location.yield_self do |location|
                path = Pathname(location.buffer.name)
                {
                  uri: URI.parse(project.absolute_path(path).to_s).tap {|uri| uri.scheme = "file" },
                  range: {
                    start: { line: location.start_line - 1, character: location.start_column },
                    end: { line: location.end_line - 1, character: location.end_column }
                  }
                }
              end,
              container_name: symbol.container_name
            )
          end
        end
      end

      def stats_result
        calculator = Services::StatsCalculator.new(service: service)

        project.targets.each.with_object([]) do |target, stats|
          service.source_files.each_value do |file|
            next unless assignment =~ file.path
            next unless target.possible_source_file?(file.path)

            stats << calculator.calc_stats(target, file: file)
          end
        end
      end
    end
  end
end
