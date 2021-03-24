module Steep
  module Server
    class TypeCheckWorker < BaseWorker
      attr_reader :project, :assignment, :service
      attr_reader :commandline_args
      attr_reader :current_type_check_guid

      WorkspaceSymbolJob = Struct.new(:query, :id, keyword_init: true)
      StatsJob = Struct.new(:id, keyword_init: true)
      StartTypeCheckJob = Struct.new(:guid, :changes, keyword_init: true)
      TypeCheckCodeJob = Struct.new(:guid, :path, keyword_init: true)
      ValidateAppSignatureJob = Struct.new(:guid, :path, keyword_init: true)
      ValidateLibrarySignatureJob = Struct.new(:guid, :path, keyword_init: true)

      include ChangeBuffer

      def initialize(project:, reader:, writer:, assignment:, commandline_args:)
        super(project: project, reader: reader, writer: writer)

        @assignment = assignment
        @service = Services::TypeCheckService.new(project: project)
        @buffered_changes = {}
        @mutex = Mutex.new()
        @queue = Queue.new
        @commandline_args = commandline_args
        @current_type_check_guid = nil
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
          enqueue_typecheck_jobs(params)
        end
      end

      def enqueue_typecheck_jobs(params)
        guid = params[:guid]

        @current_type_check_guid = guid

        pop_buffer() do |changes|
          Steep.logger.info { "Enqueueing StartTypeCheckJob for guid=#{guid}" }
          queue << StartTypeCheckJob.new(guid: guid, changes: changes)
        end

        priority_paths = Set.new(params[:priority_uris].map {|uri| Pathname(URI.parse(uri).path) })
        library_paths = params[:library_uris].map {|uri| Pathname(URI.parse(uri).path) }
        signature_paths = params[:signature_uris].map {|uri| Pathname(URI.parse(uri).path) }
        code_paths = params[:code_uris].map {|uri| Pathname(URI.parse(uri).path) }

        library_paths.each do |path|
          if priority_paths.include?(path)
            Steep.logger.info { "Enqueueing ValidateLibrarySignatureJob for guid=#{guid}, path=#{path}" }
            queue << ValidateLibrarySignatureJob.new(guid: guid, path: path)
          end
        end

        code_paths.each do |path|
          if priority_paths.include?(path)
            Steep.logger.info { "Enqueueing TypeCheckCodeJob for guid=#{guid}, path=#{path}" }
            queue << TypeCheckCodeJob.new(guid: guid, path: path)
          end
        end

        signature_paths.each do |path|
          if priority_paths.include?(path)
            Steep.logger.info { "Enqueueing ValidateAppSignatureJob for guid=#{guid}, path=#{path}" }
            queue << ValidateAppSignatureJob.new(guid: guid, path: path)
          end
        end

        library_paths.each do |path|
          unless priority_paths.include?(path)
            Steep.logger.info { "Enqueueing ValidateLibrarySignatureJob for guid=#{guid}, path=#{path}" }
            queue << ValidateLibrarySignatureJob.new(guid: guid, path: path)
          end
        end

        code_paths.each do |path|
          unless priority_paths.include?(path)
            Steep.logger.info { "Enqueueing TypeCheckCodeJob for guid=#{guid}, path=#{path}" }
            queue << TypeCheckCodeJob.new(guid: guid, path: path)
          end
        end

        signature_paths.each do |path|
          unless priority_paths.include?(path)
            Steep.logger.info { "Enqueueing ValidateAppSignatureJob for guid=#{guid}, path=#{path}" }
            queue << ValidateAppSignatureJob.new(guid: guid, path: path)
          end
        end
      end

      def handle_job(job)
        case job
        when StartTypeCheckJob
          Steep.logger.info { "Processing StartTypeCheckJob for guid=#{job.guid}" }
          service.update(changes: job.changes)

        when ValidateAppSignatureJob
          if job.guid == current_type_check_guid
            Steep.logger.info { "Processing ValidateAppSignature for guid=#{job.guid}, path=#{job.path}" }
            service.validate_signature(path: project.relative_path(job.path)) do |path, diagnostics|
              formatter = Diagnostic::LSPFormatter.new()

              writer.write(
                method: :"textDocument/publishDiagnostics",
                params: LSP::Interface::PublishDiagnosticsParams.new(
                  uri: URI.parse(job.path.to_s).tap {|uri| uri.scheme = "file"},
                  diagnostics: diagnostics.map {|diagnostic| formatter.format(diagnostic) }.uniq
                )
              )
            end

            typecheck_progress(path: job.path, guid: job.guid)
          end

        when ValidateLibrarySignatureJob
          if job.guid == current_type_check_guid
            Steep.logger.info { "Processing ValidateLibrarySignature for guid=#{job.guid}, path=#{job.path}" }
            service.validate_signature(path: job.path) do |path, diagnostics|
              formatter = Diagnostic::LSPFormatter.new()

              writer.write(
                method: :"textDocument/publishDiagnostics",
                params: LSP::Interface::PublishDiagnosticsParams.new(
                  uri: URI.parse(job.path.to_s).tap {|uri| uri.scheme = "file"},
                  diagnostics: diagnostics.map {|diagnostic| formatter.format(diagnostic) }.uniq
                )
              )
            end

            typecheck_progress(path: job.path, guid: job.guid)
          end

        when TypeCheckCodeJob
          if job.guid == current_type_check_guid
            Steep.logger.info { "Processing TypeCheckCodeJob for guid=#{job.guid}, path=#{job.path}" }
            service.typecheck_source(path: project.relative_path(job.path)) do |path, diagnostics|
              if target = project.target_for_source_path(path)
                diagnostics = diagnostics.select {|diagnostic| target.options.error_to_report?(diagnostic) }
              end

              formatter = Diagnostic::LSPFormatter.new()

              writer.write(
                method: :"textDocument/publishDiagnostics",
                params: LSP::Interface::PublishDiagnosticsParams.new(
                  uri: URI.parse(job.path.to_s).tap {|uri| uri.scheme = "file"},
                  diagnostics: diagnostics.map {|diagnostic| formatter.format(diagnostic) }.uniq
                )
              )
            end

            typecheck_progress(path: job.path, guid: job.guid)
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

      def typecheck_progress(guid:, path:)
        writer.write(
          method: "$/typecheck/progress",
          params: { guid: guid, path: path }
        )
      end

      def workspace_symbol_result(query)
        Steep.measure "Generating workspace symbol list for query=`#{query}`" do
          indexes = project.targets.map {|target| service.signature_services[target.name].latest_rbs_index }

          provider = Index::SignatureSymbolProvider.new(project: project, assignment: assignment)
          provider.indexes.push(*indexes)

          symbols = provider.query_symbol(query)

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
            next unless target.possible_source_file?(file.path)
            absolute_path = project.absolute_path(file.path)
            next unless assignment =~ absolute_path

            stats << calculator.calc_stats(target, file: file)
          end
        end
      end
    end
  end
end
