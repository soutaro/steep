module Steep
  module Server
    class TypeCheckWorker < BaseWorker
      attr_reader :project, :assignment, :service

      TypeCheckJob = Class.new

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
        end
      end
    end
  end
end
