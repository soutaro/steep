module Steep
  module Server
    class CodeWorker < BaseWorker
      LSP = LanguageServer::Protocol

      TypeCheckJob = Struct.new(:target, :path, keyword_init: true)
      StatsJob = Struct.new(:request, :paths, keyword_init: true)

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
        queue << TypeCheckJob.new(target: target, path: path)
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

      def calculate_stats(request_id, paths)
        calculator = Project::StatsCalculator.new(project: project)

        stats = paths.map do |path|
          if typecheck_paths.include?(path)
            if target = project.target_for_source_path(path)
              calculator.calc_stats(target, path)
            end
          end
        end.compact

        writer.write(
          id: request_id,
          result: stats.map(&:as_json)
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
          formatter = Diagnostic::LSPFormatter.new()
          status.typing.errors.select {|error| options.error_to_report?(error) }.map {|error| formatter.format(error) }
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
          Steep.logger.info { "Executing command: #{request[:params][:command]}, arguments=#{request[:params][:arguments].map(&:inspect).join(", ")}" }
          case request[:params][:command]
          when "steep/registerSourceToWorker"
            paths = request[:params][:arguments].map {|arg| source_path(URI.parse(arg)) }
            typecheck_paths.merge(paths)
          when "steep/stats"
            paths = request[:params][:arguments].map {|arg| source_path(URI.parse(arg)) }
            queue << StatsJob.new(paths: paths, request: request)
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
        case job
        when TypeCheckJob
          typecheck_file(job.path, job.target)
        when StatsJob
          calculate_stats(job.request[:id], job.paths)
        end
      end
    end
  end
end
