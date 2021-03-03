module Steep
  module Server
    class TypeCheckWorker < BaseWorker
      attr_reader :project, :assignment, :service

      TypeCheckJob = Class.new
      WorkspaceSymbolJob = Struct.new(:query, :id, keyword_init: true)

      include ChangeBuffer

      def initialize(project:, reader:, writer:, assignment:)
        super(project: project, reader: reader, writer: writer)

        @assignment = assignment
        @service = Services::TypeCheckService.new(project: project, assignment: assignment)
        @buffered_changes = {}
        @mutex = Mutex.new()
        @queue = Queue.new
      end

      def handle_request(request)
        case request[:method]
        when "initialize"
          load_files(project: project)
          queue << TypeCheckJob.new()
          writer.write({ id: request[:id], result: nil})
        when "textDocument/didChange"
          collect_changes(request)
          queue << TypeCheckJob.new()
        when "workspace/symbol"
          query = request[:params][:query]
          queue << WorkspaceSymbolJob.new(id: request[:id], query: query)
        end
      end

      def handle_job(job)
        case job
        when TypeCheckJob
          pop_buffer() do |changes|
            break if changes.empty?

            formatter = Diagnostic::LSPFormatter.new()

            service.update(changes: changes) do |path, diagnostics|
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
    end
  end
end
