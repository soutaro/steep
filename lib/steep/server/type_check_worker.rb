module Steep
  module Server
    class TypeCheckWorker < BaseWorker
      attr_reader :project, :assignment, :service, :buffered_changes

      TypeCheckJob = Class.new

      def initialize(project:, reader:, writer:, assignment:)
        super(project: project, reader: reader, writer: writer)

        @assignment = assignment
        @service = Services::TypeCheckService.new(project: project, assignment: assignment)
        @buffered_changes = {}
        @mutex = Mutex.new()
        @queue = Queue.new
      end

      def push_buffer
        @mutex.synchronize do
          yield buffered_changes
        end
      end

      def pop_buffer
        changes = {}
        @mutex.synchronize do
          changes.merge!(buffered_changes)
          buffered_changes.clear
        end
        if block_given?
          yield changes
        else
          changes
        end
      end

      def load_files()
        push_buffer do |changes|
          loader = Project::FileLoader.new(project: project)

          project.targets.each do |target|
            loader.each_path_in_patterns(target.source_pattern) do |path|
              content = project.absolute_path(path).read()
              changes[path] = [Services::ContentChange.string(content)]
            end

            loader.each_path_in_patterns(target.signature_pattern) do |path|
              unless changes.key?(path)
                content = project.absolute_path(path).read()
                changes[path] = [Services::ContentChange.string(content)]
              end
            end
          end
        end
      end

      def collect_changes(request)
        push_buffer do |changes|
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

      def handle_request(request)
        case request[:method]
        when "initialize"
          load_files()
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
