module Steep
  module Server
    class InteractionWorker < BaseWorker
      include ChangeBuffer

      HoverJob = _ = Struct.new(:id, :path, :line, :column, keyword_init: true)
      CompletionJob = _ = Struct.new(:id, :path, :line, :column, :trigger, keyword_init: true)
      SignatureHelpJob = _ = Struct.new(:id, :path, :line, :column, keyword_init: true)

      LSP = LanguageServer::Protocol

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
            writer.write(
              {
                id: job.id,
                result: process_latest_job(job) { process_hover(job) }
              }
            )
          when CompletionJob
            writer.write(
              {
                id: job.id,
                result: process_latest_job(job) { process_completion(job) }
              }
            )
          when SignatureHelpJob
            writer.write(
              {
                id: job.id,
                result: process_latest_job(job) { process_signature_help(job) }
              }
            )
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
        when "initialize"
          writer.write({ id: request[:id], result: nil })

        when "textDocument/didChange"
          collect_changes(request)

        when CustomMethods::FileLoad::METHOD
          params = request[:params] #: CustomMethods::FileLoad::params
          input = params[:content]
          load_files(input)

        when CustomMethods::FileReset::METHOD
          params = request[:params] #: CustomMethods::FileReset::params
          uri = params[:uri]
          text = params[:content]
          reset_change(uri: uri, text: text)

        when "textDocument/hover"
          id = request[:id]

          path = project.relative_path(PathHelper.to_pathname!(request[:params][:textDocument][:uri]))
          line = request[:params][:position][:line]+1
          column = request[:params][:position][:character]

          queue_job HoverJob.new(id: id, path: path, line: line, column: column)

        when "textDocument/completion"
          id = request[:id]

          params = request[:params]

          path = project.relative_path(PathHelper.to_pathname!(params[:textDocument][:uri]))
          line, column = params[:position].yield_self {|hash| [hash[:line]+1, hash[:character]] }
          trigger = params.dig(:context, :triggerCharacter)

          queue_job CompletionJob.new(id: id, path: path, line: line, column: column, trigger: trigger)
        when "textDocument/signatureHelp"
          id = request[:id]
          params = request[:params]
          path = project.relative_path(PathHelper.to_pathname!(params[:textDocument][:uri]))
          line, column = params[:position].yield_self {|hash| [hash[:line]+1, hash[:character]] }

          queue_job SignatureHelpJob.new(id: id, path: path, line: line, column: column)
        end
      end

      def process_hover(job)
        Steep.logger.tagged "#process_hover" do
          Steep.measure "Generating hover response" do
            Steep.logger.info { "path=#{job.path}, line=#{job.line}, column=#{job.column}" }

            content = Services::HoverProvider.content_for(service: service, path: job.path, line: job.line, column: job.column)
            if content
              range = content.location.yield_self do |location|
                lsp_range = location.as_lsp_range
                start_position = LSP::Interface::Position.new(line: lsp_range[:start][:line], character: lsp_range[:start][:character])
                end_position = LSP::Interface::Position.new(line: lsp_range[:end][:line], character: lsp_range[:end][:character])
                LSP::Interface::Range.new(start: start_position, end: end_position)
              end

              LSP::Interface::Hover.new(
                contents:  LSP::Interface::MarkupContent.new(kind: "markdown", value: LSPFormatter.format_hover_content(content).to_s),
                range: range
              )
            end
          rescue Typing::UnknownNodeError => exn
            Steep.log_error exn, message: "Failed to compute hover: #{exn.inspect}"
            nil
          end
        end
      end

      def process_completion(job)
        Steep.logger.tagged("#response_to_completion") do
          Steep.measure "Generating response" do
            Steep.logger.info "path: #{job.path}, line: #{job.line}, column: #{job.column}, trigger: #{job.trigger}"

            case
            when target = project.target_for_source_path(job.path)
              file = service.source_files[job.path] or return
              subtyping = service.signature_services.fetch(target.name).current_subtyping or return

              provider = Services::CompletionProvider::Ruby.new(source_text: file.content, path: job.path, subtyping: subtyping)

              if (prefix_size, items = provider.run_at_comment(line: job.line, column: job.column))
                completion_items = items.map { format_completion_item(_1) }
                completion_items.concat builtin_types(prefix_size, job.line, job.column)
              else
                items = begin
                          provider.run(line: job.line, column: job.column)
                        rescue Parser::SyntaxError
                          [] #: Array[Services::CompletionProvider::item]
                        end

                completion_items = items.map do |item|
                  format_completion_item(item)
                end
              end

              Steep.logger.debug "items = #{completion_items.inspect}"

              LSP::Interface::CompletionList.new(
                is_incomplete: false,
                items: completion_items
              )
            when target = project.target_for_signature_path(job.path)
              sig_service = service.signature_services[target.name] or raise
              relative_path = job.path

              completion = Services::CompletionProvider::RBS.new(relative_path, sig_service)
              prefix_size, type_names = completion.run(job.line, job.column)

              completion_items = type_names.map do |absolute_name, relative_name|
                format_completion_item_for_rbs(sig_service, absolute_name, job, relative_name.to_s, prefix_size)
              end

              completion_items.concat(builtin_types(prefix_size, job.line, job.column))

              LSP::Interface::CompletionList.new(
                is_incomplete: !sig_service.status.is_a?(Services::SignatureService::LoadedStatus),
                items: completion_items
              )
            end
          end
        end
      end

      def format_completion_item_for_rbs(sig_service, type_name, job, complete_text, prefix_size)
        range = LSP::Interface::Range.new(
          start: LSP::Interface::Position.new(
            line: job.line - 1,
            character: job.column - prefix_size
          ),
          end: LSP::Interface::Position.new(
            line: job.line - 1,
            character: job.column
          )
        )

        type_name = sig_service.latest_env.normalize_type_name(type_name)

        tags = [] #: Array[LSP::Constant::CompletionItemTag::t]
        if AnnotationsHelper.deprecated_type_name?(type_name, sig_service.latest_env)
          tags << LSP::Constant::CompletionItemTag::DEPRECATED
        end

        case type_name.kind
        when :class
          env = sig_service.latest_env
          class_entry = env.module_class_entry(type_name) or raise

          case class_entry
          when RBS::Environment::ClassEntry, RBS::Environment::ModuleEntry
            comments = class_entry.each_decl.map {|decl| decl.is_a?(RBS::AST::Declarations::Base) ? decl.comment : nil }.compact
            decl = class_entry.primary_decl
          when RBS::Environment::ClassAliasEntry, RBS::Environment::ModuleAliasEntry
            comments = [class_entry.decl.comment].compact
            decl = class_entry.decl
          end

          LSP::Interface::CompletionItem.new(
            label: complete_text,
            label_details: LSP::Interface::CompletionItemLabelDetails.new(description: LSPFormatter.declaration_summary(decl)),
            documentation: LSPFormatter.markup_content { LSPFormatter.format_rbs_completion_docs(type_name, decl, comments) },
            text_edit: LSP::Interface::TextEdit.new(
              range: range,
              new_text: complete_text
            ),
            kind: LSP::Constant::CompletionItemKind::CLASS,
            tags: tags
          )
        when :alias
          alias_decl = sig_service.latest_env.type_alias_decls[type_name]&.decl or raise

          LSP::Interface::CompletionItem.new(
            label: complete_text,
            label_details: LSP::Interface::CompletionItemLabelDetails.new(description: LSPFormatter.declaration_summary(alias_decl)),
            text_edit: LSP::Interface::TextEdit.new(
              range: range,
              new_text: complete_text
            ),
            documentation: LSPFormatter.markup_content { LSPFormatter.format_rbs_completion_docs(type_name, alias_decl, [alias_decl.comment].compact) },
            kind: LSP::Constant::CompletionItemKind::FIELD,
            tags: tags
          )
        when :interface
          interface_decl = sig_service.latest_env.interface_decls[type_name]&.decl or raise

          LSP::Interface::CompletionItem.new(
            label: complete_text,
            label_details: LSP::Interface::CompletionItemLabelDetails.new(description: LSPFormatter.declaration_summary(interface_decl)),
            text_edit: LSP::Interface::TextEdit.new(
              range: range,
              new_text: complete_text
            ),
            documentation: LSPFormatter.markup_content { LSPFormatter.format_rbs_completion_docs(type_name, interface_decl, [interface_decl.comment].compact) },
            kind: LSP::Constant::CompletionItemKind::INTERFACE,
            tags: tags
          )
        else
          raise
        end
      end

      def format_completion_item(item)
        range = LSP::Interface::Range.new(
          start: LSP::Interface::Position.new(
            line: item.range.start.line-1,
            character: item.range.start.column
          ),
          end: LSP::Interface::Position.new(
            line: item.range.end.line-1,
            character: item.range.end.column
          )
        )

        case item
        when Services::CompletionProvider::LocalVariableItem
          LSP::Interface::CompletionItem.new(
            label: item.identifier.to_s,
            kind: LSP::Constant::CompletionItemKind::VARIABLE,
            label_details: LSP::Interface::CompletionItemLabelDetails.new(description: item.type.to_s),
            documentation: LSPFormatter.markup_content { LSPFormatter.format_completion_docs(item) },
            insert_text: item.identifier.to_s,
            sort_text: item.identifier.to_s
          )
        when Services::CompletionProvider::ConstantItem
          case
          when item.class? || item.module?
            kind = LSP::Constant::CompletionItemKind::CLASS
          else
            kind = LSP::Constant::CompletionItemKind::CONSTANT
          end

          detail = LSPFormatter.declaration_summary(item.decl)

          tags = [] #: Array[LSP::Constant::CompletionItemTag::t]
          if item.deprecated?
            tags << LSP::Constant::CompletionItemTag::DEPRECATED
          end

          LSP::Interface::CompletionItem.new(
            label: item.identifier.to_s,
            kind: kind,
            label_details: LSP::Interface::CompletionItemLabelDetails.new(description: detail),
            documentation: LSPFormatter.markup_content { LSPFormatter.format_completion_docs(item) },
            text_edit: LSP::Interface::TextEdit.new(
              range: range,
              new_text: item.identifier.to_s
            ),
            tags: tags
          )
        when Services::CompletionProvider::SimpleMethodNameItem
          tags = [] #: Array[LSP::Constant::CompletionItemTag::t]
          if item.deprecated
            tags << LSP::Constant::CompletionItemTag::DEPRECATED
          end

          LSP::Interface::CompletionItem.new(
            label: item.identifier.to_s,
            kind: LSP::Constant::CompletionItemKind::FUNCTION,
            label_details: LSP::Interface::CompletionItemLabelDetails.new(description: item.method_name.relative.to_s),
            insert_text: item.identifier.to_s,
            documentation: LSPFormatter.markup_content { LSPFormatter.format_completion_docs(item) },
            tags: tags
          )
        when Services::CompletionProvider::ComplexMethodNameItem
          method_names = item.method_names.map(&:relative).uniq

          LSP::Interface::CompletionItem.new(
            label: item.identifier.to_s,
            kind: LSP::Constant::CompletionItemKind::FUNCTION,
            label_details: LSP::Interface::CompletionItemLabelDetails.new(description: method_names.join(", ")),
            insert_text: item.identifier.to_s,
            documentation: LSPFormatter.markup_content { LSPFormatter.format_completion_docs(item) }
          )
        when Services::CompletionProvider::GeneratedMethodNameItem
          LSP::Interface::CompletionItem.new(
            label: item.identifier.to_s,
            kind: LSP::Constant::CompletionItemKind::FUNCTION,
            label_details: LSP::Interface::CompletionItemLabelDetails.new(description: "(Generated)"),
            insert_text: item.identifier.to_s,
            documentation: LSPFormatter.markup_content { LSPFormatter.format_completion_docs(item) }
          )
        when Services::CompletionProvider::InstanceVariableItem
          LSP::Interface::CompletionItem.new(
            label: item.identifier.to_s,
            kind: LSP::Constant::CompletionItemKind::FIELD,
            label_details: LSP::Interface::CompletionItemLabelDetails.new(description: item.type.to_s),
            documentation: LSPFormatter.markup_content { LSPFormatter.format_completion_docs(item) },
            text_edit: LSP::Interface::TextEdit.new(
              range: range,
              new_text: item.identifier.to_s
            )
          )
        when Services::CompletionProvider::KeywordArgumentItem
          LSP::Interface::CompletionItem.new(
            label: item.identifier.to_s,
            kind: LSP::Constant::CompletionItemKind::FIELD,
            label_details: LSP::Interface::CompletionItemLabelDetails.new(description: 'Keyword argument'),
            documentation: LSPFormatter.markup_content { LSPFormatter.format_completion_docs(item) },
            text_edit: LSP::Interface::TextEdit.new(
              range: range,
              new_text: item.identifier.to_s
            )
          )
        when Services::CompletionProvider::TypeNameItem
          kind =
            case
            when item.absolute_type_name.class?
              LSP::Constant::CompletionItemKind::CLASS
            when item.absolute_type_name.interface?
              LSP::Constant::CompletionItemKind::INTERFACE
            when item.absolute_type_name.alias?
              LSP::Constant::CompletionItemKind::FIELD
            end

          tags = [] #: Array[LSP::Constant::CompletionItemTag::t]
          if AnnotationsHelper.deprecated_type_name?(item.absolute_type_name, item.env)
            tags << LSP::Constant::CompletionItemTag::DEPRECATED
          end

          LSP::Interface::CompletionItem.new(
            label: item.relative_type_name.to_s,
            kind: kind,
            label_details: nil,
            documentation: LSPFormatter.markup_content { LSPFormatter.format_completion_docs(item) },
            text_edit: LSP::Interface::TextEdit.new(
              range: range,
              new_text: item.relative_type_name.to_s
            ),
            tags: tags
          )
          when Services::CompletionProvider::TextItem
            LSP::Interface::CompletionItem.new(
              label: item.label,
              label_details: item.help_text && LSP::Interface::CompletionItemLabelDetails.new(description: item.help_text),
              kind: LSP::Constant::CompletionItemKind::SNIPPET,
              insert_text_format: LSP::Constant::InsertTextFormat::SNIPPET,
              text_edit: LSP::Interface::TextEdit.new(
                range: range,
                new_text: item.text
              )
            )
        end
      end

      def process_signature_help(job)
        Steep.logger.tagged("##{__method__}") do
          if target = project.target_for_source_path(job.path)
            file = service.source_files[job.path] or return
            subtyping = service.signature_services.fetch(target.name).current_subtyping or return
            source =
              Source.parse(file.content, path: file.path, factory: subtyping.factory)
                .without_unrelated_defs(line: job.line, column: job.column)

            provider = Services::SignatureHelpProvider.new(source: source, subtyping: subtyping)

            if (items, index = provider.run(line: job.line, column: job.column))
              signatures = items.map do |item|
                params = item.parameters or raise

                LSP::Interface::SignatureInformation.new(
                  label: item.method_type.to_s,
                  parameters: params.map { |param| LSP::Interface::ParameterInformation.new(label: param)},
                  active_parameter: item.active_parameter,
                  documentation: item.comment&.yield_self do |comment|
                    LSP::Interface::MarkupContent.new(
                      kind: LSP::Constant::MarkupKind::MARKDOWN,
                      value: comment.string.gsub(/<!--(?~-->)-->/, "")
                    )
                  end
                )
              end

              @last_signature_help_line = job.line
              @last_signature_help_result = LSP::Interface::SignatureHelp.new(
                signatures: signatures,
                active_signature: index
              )
            end
          end
        end
      rescue Parser::SyntaxError
        # Reuse the latest result to keep SignatureHelp opened while typing
        @last_signature_help_result if @last_signature_help_line == job.line
      end

      def builtin_types(prefix_size, line, column)
        ["untyped", "void", "bool", "class", "module", "instance", "nil", "top", "bot"].map do |name|
          LSP::Interface::CompletionItem.new(
            label: name,
            detail: "(builtin type)",
            text_edit: LSP::Interface::TextEdit.new(
              range: LSP::Interface::Range.new(
                start: LSP::Interface::Position.new(
                  line: line - 1,
                  character: column - prefix_size
                ),
                end: LSP::Interface::Position.new(
                  line: line - 1,
                  character: column
                )
              ),
              new_text: name
            ),
            kind: LSP::Constant::CompletionItemKind::KEYWORD,
            filter_text: name,
            sort_text: "zz__#{name}"
          )
        end
      end
    end
  end
end
