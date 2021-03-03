module Steep
  module Server
    class TypeCheckWorker < BaseWorker
      attr_reader :project, :assignment, :service
      attr_reader :commandline_args

      TypeCheckJob = Class.new
      WorkspaceSymbolJob = Struct.new(:query, :id, keyword_init: true)
      StatsJob = Struct.new(:id, keyword_init: true)

      include ChangeBuffer

      def initialize(project:, reader:, writer:, assignment:, commandline_args:)
        super(project: project, reader: reader, writer: writer)

        @assignment = assignment
        @service = Services::TypeCheckService.new(project: project, assignment: assignment)
        @buffered_changes = {}
        @mutex = Mutex.new()
        @queue = Queue.new
        @commandline_args = commandline_args
      end

      def handle_request(request)
        case request[:method]
        when "initialize"
          load_files(project: project, commandline_args: commandline_args)
          queue << TypeCheckJob.new()
          writer.write({ id: request[:id], result: nil})
        when "textDocument/didChange"
          collect_changes(request)
          queue << TypeCheckJob.new()
        when "workspace/symbol"
          query = request[:params][:query]
          queue << WorkspaceSymbolJob.new(id: request[:id], query: query)
        when "workspace/executeCommand"
          case request[:params][:command]
          when "steep/stats"
            queue << StatsJob.new(id: request[:id])
          end
        end
      end

      def handle_job(job)
        case job
        when TypeCheckJob
          pop_buffer() do |changes|
            break if changes.empty?

            formatter = Diagnostic::LSPFormatter.new()

            service.update(changes: changes) do |path, diagnostics|
              if target = project.target_for_source_path(path)
                diagnostics = diagnostics.select {|diagnostic| target.options.error_to_report?(diagnostic) }
              end

              writer.write(
                method: :"textDocument/publishDiagnostics",
                params: LSP::Interface::PublishDiagnosticsParams.new(
                  uri: URI.parse(project.absolute_path(path).to_s).tap {|uri| uri.scheme = "file"},
                  diagnostics: diagnostics.map {|diagnostic| formatter.format(diagnostic) }.uniq
                )
              )
            end
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
