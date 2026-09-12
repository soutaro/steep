module Steep
  module Server
    class TypeCheckWorker < BaseWorker
      attr_reader :project, :assignment
      attr_reader :commandline_args
      attr_reader :current_type_check_guid

      WorkspaceSymbolJob = _ = Struct.new(:query, :id, keyword_init: true)
      StartTypeCheckJob = _ = Struct.new(:guid, :changes, keyword_init: true)
      TypeCheckCodeJob = _ = Struct.new(:guid, :path, :target, keyword_init: true)
      ValidateAppSignatureJob = _ = Struct.new(:guid, :path, :target, keyword_init: true)
      ValidateLibrarySignatureJob = _ = Struct.new(:guid, :path, :target, keyword_init: true)
      TypeCheckInlineCodeJob = _ = Struct.new(:guid, :path, :target, keyword_init: true)

      include ChangeBuffer

      def initialize(project:, reader:, writer:, assignment:, commandline_args:)
        super(project: project, reader: reader, writer: writer)

        @assignment = assignment
        @buffered_changes = {}
        @mutex = Mutex.new()
        @queue = Queue.new
        @commandline_args = commandline_args
        @current_type_check_guid = nil
        @rbs_entries_cache = {}
      end

      def service
        @service ||= Services::TypeCheckService.new(project: project)
      end

      def handle_request(request)
        case request[:method]
        when "initialize"
          writer.write({ id: request[:id], result: nil})

        when "textDocument/didChange"
          collect_changes(request)

        when CustomMethods::FileLoad::METHOD
          input = request[:params][:content]
          load_files(input)

        when CustomMethods::FileReset::METHOD
          params = request[:params] #: CustomMethods::FileReset::params
          uri = params[:uri]
          text = params[:content]
          reset_change(uri: uri, text: text)

        when "workspace/symbol"
          query = request[:params][:query]
          queue << WorkspaceSymbolJob.new(id: request[:id], query: query)
        when CustomMethods::TypeCheck__Start::METHOD
          params = request[:params] #: CustomMethods::TypeCheck__Start::params
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

        targets = project.targets.each.with_object({}) do |target, hash| #$ Hash[String, Project::Target]
          hash[target.name.to_s] = target
        end

        priority_paths = Set.new(params[:priority_uris].map {|uri| Steep::PathHelper.to_pathname!(uri) })
        libraries = params[:library_uris].map {|target_name, uri| [targets.fetch(target_name), Steep::PathHelper.to_pathname!(uri)] } #: Array[[Project::Target, Pathname]]
        signatures = params[:signature_uris].map {|target_name, uri| [targets.fetch(target_name), Steep::PathHelper.to_pathname!(uri)] } #: Array[[Project::Target, Pathname]]
        codes = params[:code_uris].map {|target_name, uri| [targets.fetch(target_name), Steep::PathHelper.to_pathname!(uri)] } #: Array[[Project::Target, Pathname]]
        inlines = params[:inline_uris].map {|target_name, uri| [targets.fetch(target_name), Steep::PathHelper.to_pathname!(uri)] } #: Array[[Project::Target, Pathname]]

        priority_libs, non_priority_libs = libraries.partition {|_, path| priority_paths.include?(path) }
        priority_sigs, non_priority_sigs = signatures.partition {|_, path| priority_paths.include?(path) }
        priority_codes, non_priority_codes = codes.partition {|_, path| priority_paths.include?(path) }
        priority_inlines, non_priority_inlines = inlines.partition {|_, path| priority_paths.include?(path) }

        priority_codes.each do |target, path|
          Steep.logger.info { "Enqueueing TypeCheckCodeJob for guid=#{guid}, path=#{path}, target=#{target.name}" }
          queue << TypeCheckCodeJob.new(guid: guid, path: path, target: target)
        end

        priority_sigs.each do |target, path|
          Steep.logger.info { "Enqueueing ValidateAppSignatureJob for guid=#{guid}, path=#{path}, target=#{target.name}" }
          queue << ValidateAppSignatureJob.new(guid: guid, path: path, target: target)
        end

        priority_libs.each do |target, path|
          Steep.logger.info { "Enqueueing ValidateLibrarySignatureJob for guid=#{guid}, path=#{path}, target=#{target.name}" }
          queue << ValidateLibrarySignatureJob.new(guid: guid, path: path, target: target)
        end

        priority_inlines.each do |target, path|
          Steep.logger.info { "Enqueueing TypeCheckInlineCodeJob for guid=#{guid}, path=#{path}, target=#{target.name}" }
          queue << TypeCheckInlineCodeJob.new(guid: guid, path: path, target: target)
        end

        non_priority_codes.each do |target, path|
          Steep.logger.info { "Enqueueing TypeCheckCodeJob for guid=#{guid}, path=#{path}, target=#{target.name}" }
          queue << TypeCheckCodeJob.new(guid: guid, path: path, target: target)
        end

        non_priority_sigs.each do |target, path|
          Steep.logger.info { "Enqueueing ValidateAppSignatureJob for guid=#{guid}, path=#{path}, target=#{target.name}" }
          queue << ValidateAppSignatureJob.new(guid: guid, path: path, target: target)
        end

        non_priority_libs.each do |target, path|
          Steep.logger.info { "Enqueueing ValidateLibrarySignatureJob for guid=#{guid}, path=#{path}, target=#{target.name}" }
          queue << ValidateLibrarySignatureJob.new(guid: guid, path: path, target: target)
        end

        non_priority_inlines.each do |target, path|
          Steep.logger.info { "Enqueueing TypeCheckInlineCodeJob for guid=#{guid}, path=#{path}, target=#{target.name}" }
          queue << TypeCheckInlineCodeJob.new(guid: guid, path: path, target: target)
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

            formatter = Diagnostic::LSPFormatter.new({}, **{})

            relative_path = project.relative_path(job.path)
            diagnostics = service.validate_signature(path: relative_path, target: job.target)

            typecheck_progress(
              path: job.path,
              guid: job.guid,
              target: job.target,
              signature: { diagnostics: diagnostics.filter_map { formatter.format(_1) }, entries: signature_entries(job.target, relative_path), stats: nil }
            )
          end

        when ValidateLibrarySignatureJob
          if job.guid == current_type_check_guid
            Steep.logger.info { "Processing ValidateLibrarySignature for guid=#{job.guid}, path=#{job.path}" }

            formatter = Diagnostic::LSPFormatter.new({}, **{})
            diagnostics = service.validate_signature(path: job.path, target: job.target)

            typecheck_progress(
              path: job.path,
              guid: job.guid,
              target: job.target,
              signature: { diagnostics: diagnostics.filter_map { formatter.format(_1) }, entries: signature_entries(job.target, job.path), stats: nil }
            )
          end

        when TypeCheckCodeJob
          if job.guid == current_type_check_guid
            Steep.logger.info { "Processing TypeCheckCodeJob for guid=#{job.guid}, path=#{job.path}, target=#{job.target.name}" }
            group_target = project.group_for_source_path(job.path) || job.target
            formatter = Diagnostic::LSPFormatter.new(group_target.code_diagnostics_config)
            relative_path = project.relative_path(job.path)
            file = service.typecheck_source(path: relative_path, target: job.target)
            typecheck_progress(path: job.path, guid: job.guid, target: job.target, source: source_result(file, formatter))
          end

        when TypeCheckInlineCodeJob
          if job.guid == current_type_check_guid
            Steep.logger.info { "Processing TypeCheckInlineCodeJob for guid=#{job.guid}, path=#{job.path}, target=#{job.target.name}" }
            group_target = project.group_for_inline_source_path(job.path) || job.target
            formatter = Diagnostic::LSPFormatter.new(group_target.code_diagnostics_config)
            relative_path = project.relative_path(job.path)
            source = source_result(service.typecheck_source(path: relative_path, target: job.target), formatter)
            signature_diagnostics = service.validate_signature(path: relative_path, target: job.target).filter_map { formatter.format(_1) } #: Array[LanguageServer::Protocol::Interface::Diagnostic::json]?

            # Keep the diagnostics of the last type checking, as the plain Ruby files do, when the type checking is skipped and the validation finds nothing
            if source[:diagnostics].nil? && signature_diagnostics&.empty?
              signature_diagnostics = nil
            end

            typecheck_progress(
              path: job.path,
              guid: job.guid,
              target: job.target,
              source: source,
              signature: { diagnostics: signature_diagnostics, entries: signature_entries(job.target, relative_path), stats: nil }
            )
          end

        when WorkspaceSymbolJob
          writer.write(
            id: job.id,
            result: workspace_symbol_result(job.query)
          )
        end
      end

      def typecheck_progress(guid:, path:, target:, source: nil, signature: nil)
        writer.write(
          CustomMethods::TypeCheck__Progress.notification({
            guid: guid,
            path: path.to_s,
            target: target.name.to_s,
            source: source && wire_result(source),
            signature: signature && wire_result(signature)
          })
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

        index = signature_service.latest_rbs_index
        cached = @rbs_entries_cache[target.name]
        unless cached && cached[0].equal?(index)
          cached = @rbs_entries_cache[target.name] = [index, TypeCheckDatabase.rbs_entries_by_path(index)]
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
