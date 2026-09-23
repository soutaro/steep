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

      HoverJob = _ = Struct.new(:id, :path, :line, :column, keyword_init: true)
      CompletionJob = _ = Struct.new(:id, :path, :line, :column, :trigger, keyword_init: true)
      SignatureHelpJob = _ = Struct.new(:id, :path, :line, :column, keyword_init: true)
      SourceSymbolJob = _ = Struct.new(:id, :path, :line, :column, keyword_init: true)

      include ChangeBuffer

      def initialize(project:, reader:, writer:, assignment:, commandline_args:)
        super(project: project, reader: reader, writer: writer)

        @assignment = assignment
        @buffered_changes = {}
        @mutex = Mutex.new()
        @queue = WorkerQueue.new
        @commandline_args = commandline_args
        @rbs_entries_cache = {}
        @interaction_mutex = Mutex.new
        @last_interaction_job = nil
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

        when CustomMethods::Hover::METHOD
          params = request[:params] #: CustomMethods::Hover::params
          path, line, column = position_of(params)
          enqueue_interaction_job HoverJob.new(id: request[:id], path: project.relative_path(path), line: line, column: column)

        when CustomMethods::Completion::METHOD
          params = request[:params] #: CustomMethods::Completion::params
          path, line, column = position_of(params)
          enqueue_interaction_job CompletionJob.new(id: request[:id], path: project.relative_path(path), line: line, column: column, trigger: params[:trigger])

        when CustomMethods::SignatureHelp::METHOD
          params = request[:params] #: CustomMethods::SignatureHelp::params
          path, line, column = position_of(params)
          enqueue_interaction_job SignatureHelpJob.new(id: request[:id], path: project.relative_path(path), line: line, column: column)

        when CustomMethods::Source__Symbol::METHOD
          params = request[:params] #: CustomMethods::Source__Symbol::params
          path, line, column = position_of(params)
          enqueue_interaction_job SourceSymbolJob.new(id: request[:id], path: path, line: line, column: column)
        end
      end

      def position_of(params)
        [PathHelper.to_pathname!(params[:uri]), params[:position][:line] + 1, params[:position][:character]]
      end

      def enqueue_interaction_job(job)
        @interaction_mutex.synchronize do
          @last_interaction_job = job
        end

        Steep.logger.info { "Enqueueing #{job.class.name&.split("::")&.last} for id=#{job.id}, path=#{job.path}" }
        queue.push(job, urgent: true)
      end

      def process_latest_interaction_job(job)
        @interaction_mutex.synchronize do
          unless job.equal?(@last_interaction_job)
            Steep.logger.info { "Skipping #{job.class.name&.split("::")&.last} for id=#{job.id}: a newer interaction request is waiting" }
            return
          end

          @last_interaction_job = nil
        end

        yield
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
        apply_changes()

        case job
        when ValidateAppSignatureJob
          Steep.logger.info { "Processing ValidateAppSignature for id=#{job.id}, path=#{job.path}" }

          formatter = Diagnostic::LSPFormatter.new({}, **{})

          relative_path = project.relative_path(job.path)
          diagnostics = service.validate_signature(path: relative_path, target: job.target)

          respond(
            job.id,
            signature: { diagnostics: diagnostics.filter_map { formatter.format(_1) }, entries: signature_entries(job.target, relative_path), stats: nil }
          )

        when ValidateLibrarySignatureJob
          Steep.logger.info { "Processing ValidateLibrarySignature for id=#{job.id}, path=#{job.path}" }

          formatter = Diagnostic::LSPFormatter.new({}, **{})
          diagnostics = service.validate_signature(path: job.path, target: job.target)

          respond(
            job.id,
            signature: { diagnostics: diagnostics.filter_map { formatter.format(_1) }, entries: signature_entries(job.target, job.path), stats: nil }
          )

        when TypeCheckCodeJob
          Steep.logger.info { "Processing TypeCheckCodeJob for id=#{job.id}, path=#{job.path}, target=#{job.target.name}" }
          group_target = project.group_for_source_path(job.path) || job.target
          formatter = Diagnostic::LSPFormatter.new(group_target.code_diagnostics_config)
          relative_path = project.relative_path(job.path)
          file = service.typecheck_source(path: relative_path, target: job.target)
          respond(job.id, source: source_result(file, formatter))

        when TypeCheckInlineCodeJob
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
          writer.write(
            id: job.id,
            result: workspace_symbol_result(job.query)
          )

        when HoverJob
          result = process_latest_interaction_job(job) { process_hover(job) }
          writer.write(CustomMethods::Hover.response(job.id, result))

        when CompletionJob
          result = process_latest_interaction_job(job) { process_completion(job) }
          writer.write(CustomMethods::Completion.response(job.id, result))

        when SignatureHelpJob
          result = process_latest_interaction_job(job) { process_signature_help(job) }
          writer.write(CustomMethods::SignatureHelp.response(job.id, result))

        when SourceSymbolJob
          result = process_latest_interaction_job(job) { process_source_symbol(job) }
          result ||= {} #: CustomMethods::Source__Symbol::result
          writer.write(CustomMethods::Source__Symbol.response(job.id, result))
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

      def process_source_symbol(job)
        Steep.logger.tagged "#process_source_symbol" do
          Steep.measure "Resolving the symbols at the position" do
            Steep.logger.info { "path=#{job.path}, line=#{job.line}, column=#{job.column}" }

            result = Services::SymbolProvider.new(service: service).symbols_at(path: job.path, line: job.line, column: job.column)

            wire = {} #: CustomMethods::Source__Symbol::result
            wire[:constant] = result.constant.to_s if result.constant
            wire[:type_name] = result.type_name.to_s if result.type_name
            wire[:method_names] = result.method_names.map(&:to_s) unless result.method_names.empty?
            wire[:type] = result.type.to_s if result.type
            wire
          end
        end
      end

      def process_hover(job)
        Steep.logger.tagged "#process_hover" do
          Steep.measure "Generating hover response" do
            Steep.logger.info { "path=#{job.path}, line=#{job.line}, column=#{job.column}" }

            target = target_for(job.path) or return
            content = Services::HoverProvider.content_for(service: service, path: job.path, line: job.line, column: job.column) or return

            {
              target: target.name.to_s,
              range: content.location.as_lsp_range,
              content: hover_content(content)
            }
          rescue Typing::UnknownNodeError => exn
            Steep.log_error exn, message: "Failed to compute hover: #{exn.inspect}"
            nil
          end
        end
      end

      def hover_content(content)
        case content
        when Services::HoverProvider::VariableContent
          { kind: "variable", name: content.name.to_s, type: content.type.to_s }
        when Services::HoverProvider::TypeContent
          { kind: "type", type: content.type.to_s }
        when Services::HoverProvider::TypeAssertionContent
          { kind: "type_assertion", original_type: content.original_type.to_s, asserted_type: content.asserted_type.to_s }
        when Services::HoverProvider::MethodCallContent
          call = content.method_call

          case call
          when TypeInference::MethodCall::Typed
            method_decls = call.method_decls.sort_by {|decl| decl.method_name.to_s }
            method_types = method_decls.map {|decl| decl.method_type.to_s }

            if call.is_a?(TypeInference::MethodCall::Special)
              method_types = [
                call.actual_method_type.with(
                  type: call.actual_method_type.type.with(return_type: call.return_type)
                ).to_s
              ]
            end

            {
              kind: "method_call",
              return_type: call.actual_method_type.type.return_type.to_s,
              special: call.is_a?(TypeInference::MethodCall::Special),
              error: false,
              method_types: method_types,
              methods: method_decls.map {|decl| decl.method_name.to_s }
            }
          when TypeInference::MethodCall::Error
            method_decls = call.method_decls.sort_by {|decl| decl.method_name.to_s }

            {
              kind: "method_call",
              return_type: nil,
              special: false,
              error: true,
              method_types: method_decls.map {|decl| decl.method_type.to_s },
              methods: method_decls.map {|decl| decl.method_name.to_s }
            }
          end
        when Services::HoverProvider::DefinitionContent
          {
            kind: "definition",
            method: content.method_name.to_s,
            method_type: content.method_type.to_s,
            method_types: content.definition.method_types.map(&:to_s)
          }
        when Services::HoverProvider::ConstantContent
          { kind: "constant", name: content.full_name.to_s }
        when Services::HoverProvider::TypeAliasContent, Services::HoverProvider::InterfaceTypeContent
          { kind: "type_name", name: content.decl.name.to_s }
        when Services::HoverProvider::ClassTypeContent
          { kind: "type_name", name: declared_type_name(content.decl).to_s }
        else
          raise content.class.to_s
        end
      end

      def declared_type_name(decl)
        case decl
        when RBS::AST::Declarations::Class, RBS::AST::Declarations::Module
          decl.name
        when RBS::AST::Declarations::ClassAlias, RBS::AST::Declarations::ModuleAlias
          decl.new_name
        when RBS::AST::Ruby::Declarations::ClassDecl
          decl.class_name
        when RBS::AST::Ruby::Declarations::ModuleDecl
          decl.module_name
        when RBS::AST::Ruby::Declarations::ClassModuleAliasDecl
          decl.new_name
        end
      end

      def process_completion(job)
        Steep.logger.tagged("#response_to_completion") do
          Steep.measure "Generating response" do
            Steep.logger.info "path: #{job.path}, line: #{job.line}, column: #{job.column}, trigger: #{job.trigger}"

            case
            when target = project.target_for_inline_source_path(job.path) || project.target_for_source_path(job.path)
              file = service.source_files[job.path] or return
              subtyping = service.signature_services.fetch(target.name).current_subtyping or return

              provider = Services::CompletionProvider::Ruby.new(source_text: file.content, path: job.path, subtyping: subtyping)

              if (prefix_size, items = provider.run_at_comment(line: job.line, column: job.column))
                completion_items = items.map { completion_item(_1) }
                completion_items.concat builtin_type_items(prefix_size, job.line, job.column)
              else
                items = begin
                          provider.run(line: job.line, column: job.column)
                        rescue Parser::SyntaxError
                          [] #: Array[Services::CompletionProvider::item]
                        end

                completion_items = items.map { completion_item(_1) }
              end

              Steep.logger.debug "items = #{completion_items.inspect}"

              { target: target.name.to_s, incomplete: false, items: completion_items }
            when target = project.target_for_signature_path(job.path)
              sig_service = service.signature_services[target.name] or raise

              completion = Services::CompletionProvider::RBS.new(job.path, sig_service)
              prefix_size, type_names = completion.run(job.line, job.column)
              range = range_before(job.line, job.column, prefix_size)

              completion_items = type_names.map do |absolute_name, relative_name|
                { kind: "type_name", range: range, name: relative_name.to_s, full_name: absolute_name.to_s } #: CustomMethods::Completion::type_name_item
              end #: Array[CustomMethods::Completion::item]

              completion_items.concat builtin_type_items(prefix_size, job.line, job.column)

              {
                target: target.name.to_s,
                incomplete: !sig_service.status.is_a?(Services::SignatureService::LoadedStatus),
                items: completion_items
              }
            end
          end
        end
      end

      def completion_item(item)
        range = {
          start: { line: item.range.start.line - 1, character: item.range.start.column },
          end: { line: item.range.end.line - 1, character: item.range.end.column }
        } #: CustomMethods::range

        case item
        when Services::CompletionProvider::LocalVariableItem
          { kind: "local_variable", range: range, name: item.identifier.to_s, type: item.type.to_s }
        when Services::CompletionProvider::InstanceVariableItem
          { kind: "instance_variable", range: range, name: item.identifier.to_s, type: item.type.to_s }
        when Services::CompletionProvider::ConstantItem
          { kind: "constant", range: range, name: item.identifier.to_s, full_name: item.full_name.to_s }
        when Services::CompletionProvider::SimpleMethodNameItem
          {
            kind: "method",
            range: range,
            name: item.identifier.to_s,
            method_types: item.method_types.map(&:to_s),
            methods: [item.method_name.to_s]
          }
        when Services::CompletionProvider::ComplexMethodNameItem
          {
            kind: "method",
            range: range,
            name: item.identifier.to_s,
            method_types: item.method_types.map(&:to_s),
            methods: item.method_names.map(&:to_s)
          }
        when Services::CompletionProvider::GeneratedMethodNameItem
          {
            kind: "method",
            range: range,
            name: item.identifier.to_s,
            method_types: item.method_types.map(&:to_s),
            methods: []
          }
        when Services::CompletionProvider::KeywordArgumentItem
          { kind: "keyword_argument", range: range, name: item.identifier.to_s }
        when Services::CompletionProvider::TypeNameItem
          { kind: "type_name", range: range, name: item.relative_type_name.to_s, full_name: item.absolute_type_name.to_s }
        when Services::CompletionProvider::TextItem
          { kind: "text", range: range, label: item.label, text: item.text, help_text: item.help_text }
        else
          raise
        end
      end

      def builtin_type_items(prefix_size, line, column)
        range = range_before(line, column, prefix_size)

        ["untyped", "void", "bool", "class", "module", "instance", "nil", "top", "bot"].map do |name|
          { kind: "builtin_type", range: range, name: name } #: CustomMethods::Completion::builtin_type_item
        end
      end

      def range_before(line, column, prefix_size)
        {
          start: { line: line - 1, character: column - prefix_size },
          end: { line: line - 1, character: column }
        }
      end

      def process_signature_help(job)
        Steep.logger.tagged("##{__method__}") do
          if target = project.target_for_inline_source_path(job.path) || project.target_for_source_path(job.path)
            file = service.source_files[job.path] or return
            subtyping = service.signature_services.fetch(target.name).current_subtyping or return
            source =
              Source.parse(file.content, path: file.path, factory: subtyping.factory)
                .without_unrelated_defs(line: job.line, column: job.column)

            provider = Services::SignatureHelpProvider.new(source: source, subtyping: subtyping)

            if (items, index = provider.run(line: job.line, column: job.column))
              signatures = items.map do |item|
                {
                  method_type: item.method_type.to_s,
                  parameters: item.parameters || [],
                  active_parameter: item.active_parameter,
                  method: item.method_name&.to_s
                } #: CustomMethods::SignatureHelp::signature
              end

              help = { target: target.name.to_s, signatures: signatures, active_signature: index } #: CustomMethods::SignatureHelp::help
            end
          end

          { signature_help: help, syntax_error: false }
        end
      rescue Parser::SyntaxError
        # The master keeps showing the last signature help while typing
        { signature_help: nil, syntax_error: true }
      end

      def target_for(path)
        project.target_for_inline_source_path(path) || project.target_for_source_path(path) || project.target_for_signature_path(path)
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
