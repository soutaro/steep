module Steep
  module Server
    class InteractionWorker < BaseWorker
      include ChangeBuffer

      HoverJob = _ = Struct.new(:id, :path, :line, :column, keyword_init: true)
      CompletionJob = _ = Struct.new(:id, :path, :line, :column, :trigger, keyword_init: true)
      SignatureHelpJob = _ = Struct.new(:id, :path, :line, :column, keyword_init: true)
      SourceSymbolJob = _ = Struct.new(:id, :path, :line, :column, keyword_init: true)

      attr_reader :service, :mutex

      def initialize(project:, reader:, writer:, queue: Queue.new)
        super(project: project, reader: reader, writer: writer)
        @queue = queue
        @mutex = Mutex.new
        @service = Services::TypeCheckService.new(project: project)
        @buffered_changes = {}
        @last_job_mutex = Mutex.new
      end

      def handle_job(job)
        Steep.logger.tagged "#handle_job" do
          changes = pop_buffer()

          unless changes.empty?
            Steep.logger.debug { "Applying changes for #{changes.size} files..." }
            service.update(changes: changes)
          end

          case job
          when HoverJob
            result = process_latest_job(job) { process_hover(job) }
            writer.write(CustomMethods::Hover.response(job.id, result))
          when CompletionJob
            result = process_latest_job(job) { process_completion(job) }
            writer.write(CustomMethods::Completion.response(job.id, result))
          when SignatureHelpJob
            result = process_latest_job(job) { process_signature_help(job) }
            writer.write(CustomMethods::SignatureHelp.response(job.id, result))
          when SourceSymbolJob
            result = process_latest_job(job) { process_source_symbol(job) }
            result ||= {} #: CustomMethods::Source__Symbol::result
            writer.write(CustomMethods::Source__Symbol.response(job.id, result))
          end
        end
      end

      def process_latest_job(job)
        @last_job_mutex.synchronize do
          unless job.equal?(@last_job)
            Steep.logger.debug { "Skipping interaction job: latest_job=#{@last_job.class}, skipped_job#{job.class}" }
            return
          end
          @last_job = nil
        end

        yield
      end

      def queue_job(job)
        @last_job_mutex.synchronize do
          @last_job = job
        end
        queue << job
      end

      def handle_request(request)
        case request[:method]
        when CustomMethods::FileLoad::METHOD
          params = request[:params] #: CustomMethods::FileLoad::params
          input = params[:content]
          load_files(input)

        when CustomMethods::Hover::METHOD
          id = request[:id]
          params = request[:params] #: CustomMethods::Hover::params

          path = project.relative_path(PathHelper.to_pathname!(params[:uri]))
          line = params[:position][:line] + 1
          column = params[:position][:character]

          queue_job HoverJob.new(id: id, path: path, line: line, column: column)

        when CustomMethods::Completion::METHOD
          id = request[:id]
          params = request[:params] #: CustomMethods::Completion::params

          path = project.relative_path(PathHelper.to_pathname!(params[:uri]))
          line = params[:position][:line] + 1
          column = params[:position][:character]
          trigger = params[:trigger]

          queue_job CompletionJob.new(id: id, path: path, line: line, column: column, trigger: trigger)

        when CustomMethods::SignatureHelp::METHOD
          id = request[:id]
          params = request[:params] #: CustomMethods::SignatureHelp::params

          path = project.relative_path(PathHelper.to_pathname!(params[:uri]))
          line = params[:position][:line] + 1
          column = params[:position][:character]

          queue_job SignatureHelpJob.new(id: id, path: path, line: line, column: column)

        when CustomMethods::Source__Symbol::METHOD
          id = request[:id]
          params = request[:params] #: CustomMethods::Source__Symbol::params

          path = PathHelper.to_pathname!(params[:uri])
          line = params[:position][:line] + 1
          column = params[:position][:character]

          queue_job SourceSymbolJob.new(id: id, path: path, line: line, column: column)
        end
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
                { kind: "type_name", range: range, name: relative_name.to_s, full_name: absolute_name.to_s } #: CustomMethods::Completion::item
              end

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
          { kind: "builtin_type", range: range, name: name } #: CustomMethods::Completion::item
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
    end
  end
end
