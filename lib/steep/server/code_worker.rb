module Steep
  module Server
    class CodeWorker < BaseWorker
      LSP = LanguageServer::Protocol

      include Utils

      attr_reader :target_files
      attr_reader :queue

      def initialize(project:, reader:, writer:, queue: Queue.new)
        super(project: project, reader: reader, writer: writer)

        @target_files = {}
        @queue = queue
      end

      def enqueue_type_check(target:, path:, version: target_files[path])
        Steep.logger.info "Enqueueing type check: #{path}(#{version})@#{target.name}..."
        target_files[path] = version
        queue << [path, version, target]
      end

      def each_type_check_subject(path:, version:)
        case
        when !(updated_targets = project.targets.select {|target| target.signature_file?(path) }).empty?
          updated_targets.each do |target|
            target_files.each_key do |path|
              if target.source_file?(path)
                yield target, path, target_files[path]
              end
            end
          end

        when target = project.targets.find {|target| target.source_file?(path) }
          if target_files.key?(path)
            yield target, path, version
          end
        end
      end

      def typecheck_file(path, target)
        Steep.logger.info "Starting type checking: #{path}@#{target.name}..."

        source = target.source_files[path]
        target.type_check(target_sources: [source], validate_signatures: false)

        Steep.logger.info "Finished type checking: #{path}@#{target.name}"

        diagnostics = source_diagnostics(source)

        writer.write(
          method: :"textDocument/publishDiagnostics",
          params: LSP::Interface::PublishDiagnosticsParams.new(
            uri: URI.parse(project.absolute_path(path).to_s).tap {|uri| uri.scheme = "file"},
            diagnostics: diagnostics
          )
        )
      end

      def source_diagnostics(source)
        case status = source.status
        when Project::SourceFile::ParseErrorStatus
          []
        when Project::SourceFile::AnnotationSyntaxErrorStatus
          [
            LSP::Interface::Diagnostic.new(
              message: "Annotation syntax error: #{status.error.cause.message}",
              severity: LSP::Constant::DiagnosticSeverity::ERROR,
              range: LSP::Interface::Range.new(
                start: LSP::Interface::Position.new(
                  line: status.location.start_line - 1,
                  character: status.location.start_column
                ),
                end: LSP::Interface::Position.new(
                  line: status.location.end_line - 1,
                  character: status.location.end_column
                )
              )
            )
          ]
        when Project::SourceFile::TypeCheckStatus
          status.typing.errors.map do |error|
            loc = error.location_to_str

            LSP::Interface::Diagnostic.new(
              message: StringIO.new.tap {|io| error.print_to(io) }.string.gsub(/\A#{loc}: /, "").chomp,
              severity: LSP::Constant::DiagnosticSeverity::ERROR,
              range: LSP::Interface::Range.new(
                start: LSP::Interface::Position.new(
                  line: error.node.loc.line - 1,
                  character: error.node.loc.column
                ),
                end: LSP::Interface::Position.new(
                  line: error.node.loc.last_line - 1,
                  character: error.node.loc.last_column
                )
              )
            )
          end
        when Project::SourceFile::TypeCheckErrorStatus
          []
        end
      end

      def handle_request(request)
        case request[:method]
        when "initialize"
          # Don't respond to initialize request, but start type checking.
          project.targets.each do |target|
            target.source_files.each_key do |path|
              if target_files.key?(path)
                enqueue_type_check(target: target, path: path, version: target_files[path])
              end
            end
          end

        when "workspace/executeCommand"
          if request[:params][:command] == "steep/registerSourceToWorker"
            paths = request[:params][:arguments].map {|arg| source_path(URI.parse(arg)) }
            paths.each do |path|
              target_files[path] = 0
            end
          end

        when "textDocument/didChange"
          update_source(request) do |path, version|
            if target_files.key?(path)
              target_files[path] = version
            end
          end

          path = source_path(URI.parse(request[:params][:textDocument][:uri]))
          version = request[:params][:textDocument][:version]
          each_type_check_subject(path: path, version: version) do |target, path, version|
            enqueue_type_check(target: target, path: path, version: version)
          end
        end
      end

      def handle_job(job)
        path, version, target = job
        if !version || target_files[path] == version
          typecheck_file(path, target)
        else
          Steep.logger.info "Skipping type check: #{path}@#{target.name}, queued version=#{version}, latest version=#{target_files[path]}"
        end
      end
    end
  end
end
