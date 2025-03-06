module Steep
  module Server
    class TypeCheckWorker < BaseWorker
      attr_reader :project, :assignment, :service
      attr_reader :commandline_args
      attr_reader :current_type_check_guid

      WorkspaceSymbolJob = _ = Struct.new(:query, :id, keyword_init: true)
      StatsJob = _ = Struct.new(:id, keyword_init: true)
      StartTypeCheckJob = _ = Struct.new(:guid, :changes, keyword_init: true)
      TypeCheckCodeJob = _ = Struct.new(:guid, :path, :target, keyword_init: true)
      ValidateAppSignatureJob = _ = Struct.new(:guid, :path, :target, keyword_init: true)
      ValidateLibrarySignatureJob = _ = Struct.new(:guid, :path, :target, keyword_init: true)
      class GotoJob < Struct.new(:id, :kind, :params, keyword_init: true)
        def self.implementation(id:, params:)
          new(
            kind: :implementation,
            id: id,
            params: params
          )
        end

        def self.definition(id:, params:)
          new(
            kind: :definition,
            id: id,
            params: params
          )
        end

        def self.type_definition(id:, params:)
          new(
            kind: :type_definition,
            id: id,
            params: params
          )
        end

        def implementation?
          kind == :implementation
        end

        def definition?
          kind == :definition
        end

        def type_definition?
          kind == :type_definition
        end
      end

      include ChangeBuffer

      attr_reader :io_socket

      def initialize(project:, reader:, writer:, assignment:, commandline_args:, io_socket: nil, buffered_changes: nil, service: nil)
        super(project: project, reader: reader, writer: writer)

        @assignment = assignment
        @buffered_changes = buffered_changes || {}
        @mutex = Mutex.new()
        @queue = Queue.new
        @commandline_args = commandline_args
        @current_type_check_guid = nil
        @io_socket = io_socket
        @service = service if service
        @child_pids = []

        if io_socket
          Signal.trap "SIGCHLD" do
            while pid = Process.wait(-1, Process::WNOHANG)
              raise "Unexpected worker process exit: #{pid}" if @child_pids.include?(pid)
            end
          end
        end
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
        when CustomMethods::Stats::METHOD
          queue << StatsJob.new(id: request[:id])
        when CustomMethods::TypeCheck__Start::METHOD
          params = request[:params] #: CustomMethods::TypeCheck__Start::params
          enqueue_typecheck_jobs(params)
        when "textDocument/definition"
          queue << GotoJob.definition(id: request[:id], params: request[:params])
        when "textDocument/implementation"
          queue << GotoJob.implementation(id: request[:id], params: request[:params])
        when "textDocument/typeDefinition"
          queue << GotoJob.type_definition(id: request[:id], params: request[:params])
        when CustomMethods::Refork::METHOD
          io_socket or raise

          # Receive IOs before fork to avoid receiving them from multiple processes
          stdin = io_socket.recv_io
          stdout = io_socket.recv_io

          if pid = fork
            stdin.close
            stdout.close
            @child_pids << pid
            writer.write(CustomMethods::Refork.response(request[:id], { pid: }))
          else
            io_socket.close

            reader.close
            writer.close

            reader = LanguageServer::Protocol::Transport::Io::Reader.new(stdin)
            writer = LanguageServer::Protocol::Transport::Io::Writer.new(stdout)
            Steep.logger.info("Reforked worker: #{Process.pid}, params: #{request[:params]}")
            index = request[:params][:index]
            assignment = Services::PathAssignment.new(max_index: request[:params][:max_index], index: index)

            worker = self.class.new(project: project, reader: reader, writer: writer, assignment: assignment, commandline_args: commandline_args, io_socket: nil, buffered_changes: buffered_changes, service: service)

            tags = Steep.logger.formatter.current_tags.dup
            tags[tags.find_index("typecheck:typecheck@0")] = "typecheck:typecheck@#{index}-reforked"
            Steep.logger.formatter.push_tags(tags)
            worker.run()

            raise "unreachable"
          end
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

        priority_libs, non_priority_libs = libraries.partition {|_, path| priority_paths.include?(path) }
        priority_sigs, non_priority_sigs = signatures.partition {|_, path| priority_paths.include?(path) }
        priority_codes, non_priority_codes = codes.partition {|_, path| priority_paths.include?(path) }

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

            diagnostics = service.validate_signature(path: project.relative_path(job.path), target: job.target)

            typecheck_progress(
              path: job.path,
              guid: job.guid,
              target: job.target,
              diagnostics: diagnostics.filter_map { formatter.format(_1) }
            )
          end

        when ValidateLibrarySignatureJob
          if job.guid == current_type_check_guid
            Steep.logger.info { "Processing ValidateLibrarySignature for guid=#{job.guid}, path=#{job.path}" }

            formatter = Diagnostic::LSPFormatter.new({}, **{})
            diagnostics = service.validate_signature(path: job.path, target: job.target)

            typecheck_progress(path: job.path, guid: job.guid, target: job.target, diagnostics: diagnostics.filter_map { formatter.format(_1) })
          end

        when TypeCheckCodeJob
          if job.guid == current_type_check_guid
            Steep.logger.info { "Processing TypeCheckCodeJob for guid=#{job.guid}, path=#{job.path}, target=#{job.target.name}" }
            group_target = project.group_for_source_path(job.path) || job.target
            formatter = Diagnostic::LSPFormatter.new(group_target.code_diagnostics_config)
            relative_path = project.relative_path(job.path)
            diagnostics = service.typecheck_source(path: relative_path, target: job.target)
            typecheck_progress(path: job.path, guid: job.guid, target: job.target, diagnostics: diagnostics&.filter_map { formatter.format(_1) })
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
        when GotoJob
          writer.write(
            id: job.id,
            result: goto(job)
          )
        end
      end

      def typecheck_progress(guid:, path:, target:, diagnostics:)
        writer.write(CustomMethods::TypeCheck__Progress.notification({ guid: guid, path: path.to_s, target: target.name.to_s, diagnostics: diagnostics }))
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

      def stats_result
        calculator = Services::StatsCalculator.new(service: service)

        project.targets.each.with_object([]) do |target, stats|
          service.source_files.each_value do |file|
            next unless target.possible_source_file?(file.path)
            absolute_path = project.absolute_path(file.path)
            next unless assignment =~ [target, absolute_path]

            stats << calculator.calc_stats(target, file: file)
          end
        end
      end

      def goto(job)
        path = Steep::PathHelper.to_pathname(job.params[:textDocument][:uri]) or return []
        line = job.params[:position][:line] + 1
        column = job.params[:position][:character]

        goto_service = Services::GotoService.new(type_check: service, assignment: assignment)
        locations =
          case
          when job.definition?
            goto_service.definition(path: path, line: line, column: column)
          when job.implementation?
            goto_service.implementation(path: path, line: line, column: column)
          when job.type_definition?
            goto_service.type_definition(path: path, line: line, column: column)
          else
            raise
          end

        locations.map do |loc|
          path =
            case loc
            when RBS::Location
              Pathname(loc.buffer.name)
            else
              Pathname(loc.source_buffer.name)
            end

          path = project.absolute_path(path)

          {
            uri: Steep::PathHelper.to_uri(path).to_s,
            range: loc.as_lsp_range
          }
        end
      end
    end
  end
end
