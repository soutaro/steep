module Steep
  module Server
    class CodeWorker < BaseWorker
      LSP = LanguageServer::Protocol

      include Utils

      attr_reader :typecheck_paths
      attr_reader :queue

      def initialize(project:, reader:, writer:, queue: Queue.new)
        super(project: project, reader: reader, writer: writer)

        @typecheck_paths = Set[]
        @queue = queue
      end

      def enqueue_type_check(target:, path:)
        Steep.logger.info "Enqueueing type check: #{target.name}::#{path}..."
        queue << [target, path]
      end

      def typecheck_file(path, target)
        Steep.logger.info "Starting type checking: #{target.name}::#{path}..."

        source = target.source_files[path]
        target.type_check(target_sources: [source], validate_signatures: false)

        if target.status.is_a?(Project::Target::TypeCheckStatus) && target.status.type_check_sources.empty?
          Steep.logger.debug "Skipped type checking: #{target.name}::#{path}"
        else
          Steep.logger.info "Finished type checking: #{target.name}::#{path}"
        end

        diagnostics = source_diagnostics(source, target.options)

        writer.write(
          method: :"textDocument/publishDiagnostics",
          params: LSP::Interface::PublishDiagnosticsParams.new(
            uri: URI.parse(project.absolute_path(path).to_s).tap {|uri| uri.scheme = "file"},
            diagnostics: diagnostics
          )
        )
      end

      def source_diagnostics(source, options)
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
          status.typing.errors.select {|error| options.error_to_report?(error) }.map do |error|
            loc = error.location_to_str

            LSP::Interface::Diagnostic.new(
              message: StringIO.new.tap {|io| error.print_to(io) }.string.gsub(/\A#{Regexp.escape(loc)}: /, "").chomp,
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
          project.targets.each do |target|
            target.source_files.each_key do |path|
              if typecheck_paths.include?(path)
                enqueue_type_check(target: target, path: path)
              end
            end
          end

          writer.write({ id: request[:id], result: nil })

        when "workspace/executeCommand"
          if request[:params][:command] == "steep/registerSourceToWorker"
            paths = request[:params][:arguments].map {|arg| source_path(URI.parse(arg)) }
            Steep.logger.info "Registering paths: #{paths.join(", ")}"
            typecheck_paths.merge(paths)
          end

        when "textDocument/didChange"
          update_source(request) do |path, _|
            source_target, signature_targets = project.targets_for_path(path)

            if source_target
              if typecheck_paths.include?(path)
                enqueue_type_check(target: source_target, path: path)
              end
            end

            signature_targets.each do |target|
              target.source_files.each_key do |source_path|
                if typecheck_paths.include?(source_path)
                  enqueue_type_check(target: target, path: source_path)
                end
              end
            end
          end
        end
      end

      def handle_job(job)
        target, path = job

        typecheck_file(path, target)
      end
    end
  end
end
