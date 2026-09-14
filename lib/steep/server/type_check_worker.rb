module Steep
  module Server
    class TypeCheckWorker < BaseWorker
      attr_reader :project, :assignment
      attr_reader :commandline_args

      WorkspaceSymbolJob = _ = Struct.new(:query, :id, keyword_init: true)
      TypeCheckCodeJob = _ = Struct.new(:id, :path, :target, keyword_init: true)
      ValidateAppSignatureJob = _ = Struct.new(:id, :path, :target, keyword_init: true)
      ValidateLibrarySignatureJob = _ = Struct.new(:id, :path, :target, keyword_init: true)
      TypeCheckInlineCodeJob = _ = Struct.new(:id, :path, :target, keyword_init: true)

      include ChangeBuffer

      def initialize(project:, reader:, writer:, assignment:, commandline_args:)
        super(project: project, reader: reader, writer: writer)

        @assignment = assignment
        @buffered_changes = {}
        @mutex = Mutex.new()
        @queue = Queue.new
        @commandline_args = commandline_args
        @rbs_entries_cache = {}
      end

      def service
        @service ||= Services::TypeCheckService.new(project: project)
      end

      def handle_request(request)
        case request[:method]
        when CustomMethods::FileLoad::METHOD
          input = request[:params][:content]
          load_files(input)

        when "workspace/symbol"
          query = request[:params][:query]
          queue << WorkspaceSymbolJob.new(id: request[:id], query: query)
        when CustomMethods::TypeCheck__File::METHOD
          params = request[:params] #: CustomMethods::TypeCheck__File::params
          enqueue_typecheck_job(request[:id], params)
        end
      end

      def enqueue_typecheck_job(id, params)
        target = project.targets.find {|target| target.name.to_s == params[:target] } or raise "Unknown target: #{params[:target]}"
        path = Steep::PathHelper.to_pathname!(params[:uri])

        if content = params[:content]
          load_files({ project.relative_path(path).to_s => content })
        end

        job =
          case params[:kind]
          when "code"
            TypeCheckCodeJob.new(id: id, path: path, target: target)
          when "signature"
            ValidateAppSignatureJob.new(id: id, path: path, target: target)
          when "library"
            ValidateLibrarySignatureJob.new(id: id, path: path, target: target)
          when "inline"
            TypeCheckInlineCodeJob.new(id: id, path: path, target: target)
          else
            raise "Unknown kind of type check: #{params[:kind]}"
          end

        Steep.logger.info { "Enqueueing #{job.class.name&.split("::")&.last} for id=#{id}, path=#{path}, target=#{target.name}" }
        queue << job
      end

      def handle_job(job)
        case job
        when ValidateAppSignatureJob
          apply_changes()
          Steep.logger.info { "Processing ValidateAppSignature for id=#{job.id}, path=#{job.path}" }

          formatter = Diagnostic::LSPFormatter.new({}, **{})

          relative_path = project.relative_path(job.path)
          diagnostics = service.validate_signature(path: relative_path, target: job.target)

          respond(
            job.id,
            signature: { diagnostics: diagnostics.filter_map { formatter.format(_1) }, entries: signature_entries(job.target, relative_path), stats: nil }
          )

        when ValidateLibrarySignatureJob
          apply_changes()
          Steep.logger.info { "Processing ValidateLibrarySignature for id=#{job.id}, path=#{job.path}" }

          formatter = Diagnostic::LSPFormatter.new({}, **{})
          diagnostics = service.validate_signature(path: job.path, target: job.target)

          respond(
            job.id,
            signature: { diagnostics: diagnostics.filter_map { formatter.format(_1) }, entries: signature_entries(job.target, job.path), stats: nil }
          )

        when TypeCheckCodeJob
          apply_changes()
          Steep.logger.info { "Processing TypeCheckCodeJob for id=#{job.id}, path=#{job.path}, target=#{job.target.name}" }
          group_target = project.group_for_source_path(job.path) || job.target
          formatter = Diagnostic::LSPFormatter.new(group_target.code_diagnostics_config)
          relative_path = project.relative_path(job.path)
          file = service.typecheck_source(path: relative_path, target: job.target)
          respond(job.id, source: source_result(file, formatter))

        when TypeCheckInlineCodeJob
          apply_changes()
          Steep.logger.info { "Processing TypeCheckInlineCodeJob for id=#{job.id}, path=#{job.path}, target=#{job.target.name}" }
          group_target = project.group_for_inline_source_path(job.path) || job.target
          formatter = Diagnostic::LSPFormatter.new(group_target.code_diagnostics_config)
          relative_path = project.relative_path(job.path)
          source = source_result(service.typecheck_source(path: relative_path, target: job.target), formatter)
          signature_diagnostics = service.validate_signature(path: relative_path, target: job.target).filter_map { formatter.format(_1) } #: Array[LanguageServer::Protocol::Interface::Diagnostic::json]?

          # Keep the diagnostics of the last type checking, as the plain Ruby files do, when the type checking is skipped and the validation finds nothing
          if source[:diagnostics].nil? && signature_diagnostics&.empty?
            signature_diagnostics = nil
          end

          respond(
            job.id,
            source: source,
            signature: { diagnostics: signature_diagnostics, entries: signature_entries(job.target, relative_path), stats: nil }
          )

        when WorkspaceSymbolJob
          apply_changes()
          writer.write(
            id: job.id,
            result: workspace_symbol_result(job.query)
          )
        end
      end

      def apply_changes
        pop_buffer do |changes|
          unless changes.empty?
            Steep.logger.info { "Applying the changes of #{changes.size} files..." }
            service.update(changes: changes)
          end
        end
      end

      def respond(id, source: nil, signature: nil)
        writer.write(
          CustomMethods::TypeCheck__File.response(
            id,
            { source: source && wire_result(source), signature: signature && wire_result(signature) }
          )
        )
      end

      def wire_result(result)
        { diagnostics: result[:diagnostics], entries: result[:entries]&.map { _1.to_wire }, stats: result[:stats] }
      end

      def source_result(file, formatter)
        if file
          typing = file.typing
          {
            diagnostics: file.diagnostics.filter_map { formatter.format(_1) },
            entries: typing ? TypeCheckDatabase.entries_from(typing) : nil,
            stats: typing ? Services::StatsCalculator.count_calls(typing) : nil
          }
        else
          { diagnostics: nil, entries: nil, stats: nil }
        end
      end

      def signature_entries(target, path)
        signature_service = service.signature_services.fetch(target.name)
        return unless signature_service.status.is_a?(Services::SignatureService::LoadedStatus)

        env = signature_service.latest_env
        cached = @rbs_entries_cache[target.name]
        unless cached && cached[0].equal?(env)
          cached = @rbs_entries_cache[target.name] = [env, TypeCheckDatabase.rbs_entries_by_path(env)]
        end

        cached[1][path] || []
      end

      def workspace_symbol_result(query)
        Steep.measure "Generating workspace symbol list for query=`#{query}`" do
          provider = Index::SignatureSymbolProvider.new(project: project, assignment: assignment)
          project.targets.each do |target|
            index = service.signature_services.fetch(target.name).latest_rbs_index
            provider.indexes[target] = index
          end

          symbols = provider.query_symbol(query)

          symbols.map do |symbol|
            LSP::Interface::SymbolInformation.new(
              name: symbol.name,
              kind: symbol.kind,
              location: symbol.location.yield_self do |location|
                path = Pathname(location.buffer.name)
                {
                  uri: Steep::PathHelper.to_uri(project.absolute_path(path)),
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
