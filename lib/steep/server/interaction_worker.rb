module Steep
  module Server
    class InteractionWorker < BaseWorker
      include ChangeBuffer

      ApplyChangeJob = Class.new()
      HoverJob = Struct.new(:id, :path, :line, :column, keyword_init: true)
      CompletionJob = Struct.new(:id, :path, :line, :column, :trigger, keyword_init: true)

      LSP = LanguageServer::Protocol

      attr_reader :service

      def initialize(project:, reader:, writer:, queue: Queue.new)
        super(project: project, reader: reader, writer: writer)
        @queue = queue
        @service = Services::TypeCheckService.new(project: project)
        @mutex = Mutex.new
        @buffered_changes = {}
      end

      def handle_job(job)
        Steep.logger.tagged "#handle_job" do
          changes = pop_buffer()

          unless changes.empty?
            Steep.logger.debug { "Applying changes for #{changes.size} files..." }
            service.update(changes: changes)
          end

          case job
          when ApplyChangeJob
            # nop
          when HoverJob
            writer.write({ id: job.id, result: process_hover(job) })
          when CompletionJob
            writer.write({ id: job.id, result: process_completion(job) })
          end
        end
      end

      def handle_request(request)
        case request[:method]
        when "initialize"
          load_files(project: project, commandline_args: [])
          queue << ApplyChangeJob.new
          writer.write({ id: request[:id], result: nil })

        when "textDocument/didChange"
          collect_changes(request)
          queue << ApplyChangeJob.new

        when "textDocument/hover"
          id = request[:id]

          path = project.relative_path(Steep::PathHelper.to_pathname(request[:params][:textDocument][:uri]))
          line = request[:params][:position][:line]+1
          column = request[:params][:position][:character]

          queue << HoverJob.new(id: id, path: path, line: line, column: column)

        when "textDocument/completion"
          id = request[:id]

          params = request[:params]
          path = project.relative_path(Steep::PathHelper.to_pathname(params[:textDocument][:uri]))
          line, column = params[:position].yield_self {|hash| [hash[:line]+1, hash[:character]] }
          trigger = params.dig(:context, :triggerCharacter)

          queue << CompletionJob.new(id: id, path: path, line: line, column: column, trigger: trigger)
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
                start_position = { line: lsp_range[:start][:line], character: lsp_range[:start][:character] }
                end_position = { line: lsp_range[:end][:line], character: lsp_range[:end][:character] }
                { start: start_position, end: end_position }
              end

              LSP::Interface::Hover.new(
                contents: {
                  kind: "markdown",
                  value: LSPFormatter.format_hover_content(content).to_s
                },
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
              subtyping = service.signature_services[target.name].current_subtyping or return

              provider = Services::CompletionProvider.new(source_text: file.content, path: job.path, subtyping: subtyping)
              items = begin
                        provider.run(line: job.line, column: job.column)
                      rescue Parser::SyntaxError
                        []
                      end

              completion_items = items.map do |item|
                format_completion_item(item)
              end

              Steep.logger.debug "items = #{completion_items.inspect}"

              LSP::Interface::CompletionList.new(
                is_incomplete: false,
                items: completion_items
              )
            when (_, targets = project.targets_for_path(job.path))
              target = targets[0] or return
              sig_service = service.signature_services[target.name]
              relative_path = job.path
              buffer = RBS::Buffer.new(name: relative_path, content: sig_service.files[relative_path].content)
              pos = buffer.loc_to_pos([job.line, job.column])
              prefix = buffer.content[0...pos].reverse[/\A[\w\d]*/].reverse

              case sig_service.status
              when Steep::Services::SignatureService::SyntaxErrorStatus, Steep::Services::SignatureService::AncestorErrorStatus
                return
              end

              decls = sig_service.files[relative_path].decls
              locator = RBS::Locator.new(decls: decls)

              hd, tail = locator.find2(line: job.line, column: job.column)

              namespace = []
              tail.each do |t|
                case t
                when RBS::AST::Declarations::Module, RBS::AST::Declarations::Class
                  namespace << t.name.to_namespace
                end
              end
              context = []

              namespace.each do |ns|
                context.map! { |n| ns + n }
                context << ns
              end

              context.map!(&:absolute!)

              class_items = sig_service.latest_env.class_decls.keys.map { |type_name|
                format_completion_item_for_rbs(sig_service, type_name, context, job, prefix)
              }.compact

              alias_items = sig_service.latest_env.alias_decls.keys.map { |type_name|
                format_completion_item_for_rbs(sig_service, type_name, context, job, prefix)
              }.compact

              interface_items = sig_service.latest_env.interface_decls.keys.map {|type_name|
                format_completion_item_for_rbs(sig_service, type_name, context, job, prefix)
              }.compact

              completion_items = class_items + alias_items + interface_items

              LSP::Interface::CompletionList.new(
                is_incomplete: false,
                items: completion_items
              )
            end
          end
        end
      end

      def format_completion_item_for_rbs(sig_service, type_name, context, job, prefix)
        range = LanguageServer::Protocol::Interface::Range.new(
          start: LanguageServer::Protocol::Interface::Position.new(
            line: job.line - 1,
            character: job.column - prefix.size
          ),
          end: LanguageServer::Protocol::Interface::Position.new(
            line: job.line - 1,
            character: job.column
          )
        )

        name = relative_name_in_context(type_name, context).to_s

        return unless name.start_with?(prefix)

        case type_name.kind
        when :class
          class_decl = sig_service.latest_env.class_decls[type_name]&.decls[0]&.decl or raise

          LanguageServer::Protocol::Interface::CompletionItem.new(
            label: "#{name}",
            documentation:  format_comment(class_decl.comment),
            text_edit: LanguageServer::Protocol::Interface::TextEdit.new(
              range: range,
              new_text: name
            ),
            kind: LSP::Constant::CompletionItemKind::CLASS,
            insert_text_format: LSP::Constant::InsertTextFormat::SNIPPET

          )
        when :alias
          alias_decl = sig_service.latest_env.alias_decls[type_name]&.decl or raise
          LanguageServer::Protocol::Interface::CompletionItem.new(
            label: "#{name}",
            text_edit: LanguageServer::Protocol::Interface::TextEdit.new(
              range: range,
              new_text: name
            ),
            documentation: format_comment(alias_decl.comment),
            # https://github.com/microsoft/vscode-languageserver-node/blob/6d78fc4d25719b231aba64a721a606f58b9e0a5f/client/src/common/client.ts#L624-L650
            kind: LSP::Constant::CompletionItemKind::FIELD,
            insert_text_format: LSP::Constant::InsertTextFormat::SNIPPET
          )
        when :interface
          interface_decl = sig_service.latest_env.interface_decls[type_name]&.decl or raise

          LanguageServer::Protocol::Interface::CompletionItem.new(
            label: "#{name}",
            text_edit: LanguageServer::Protocol::Interface::TextEdit.new(
              range: range,
              new_text: name
            ),
            documentation: format_comment(interface_decl.comment),
            kind: LanguageServer::Protocol::Constant::CompletionItemKind::INTERFACE,
            insert_text_format: LanguageServer::Protocol::Constant::InsertTextFormat::SNIPPET
          )
        end
      end

      def format_comment(comment)
        if comment
          LSP::Interface::MarkupContent.new(
            kind: LSP::Constant::MarkupKind::MARKDOWN,
            value: comment.string.gsub(/<!--(?~-->)-->/, "")
          )
        end
      end

      def format_comments(comments)
        unless comments.empty?
          LSP::Interface::MarkupContent.new(
            kind: LSP::Constant::MarkupKind::MARKDOWN,
            value: comments.map(&:string).join("\n----\n").gsub(/<!--(?~-->)-->/, "")
          )
        end
      end

      def format_completion_item(item)
        range = LanguageServer::Protocol::Interface::Range.new(
          start: LanguageServer::Protocol::Interface::Position.new(
            line: item.range.start.line-1,
            character: item.range.start.column
          ),
          end: LanguageServer::Protocol::Interface::Position.new(
            line: item.range.end.line-1,
            character: item.range.end.column
          )
        )

        case item
        when Services::CompletionProvider::LocalVariableItem
          LanguageServer::Protocol::Interface::CompletionItem.new(
            label: item.identifier,
            kind: LanguageServer::Protocol::Constant::CompletionItemKind::VARIABLE,
            detail: item.type.to_s,
            text_edit: LanguageServer::Protocol::Interface::TextEdit.new(
              range: range,
              new_text: item.identifier
            )
          )
        when Services::CompletionProvider::ConstantItem
          case
          when item.class? || item.module?
            kind = LanguageServer::Protocol::Constant::CompletionItemKind::CLASS
            detail = item.full_name.to_s
          else
            kind = LanguageServer::Protocol::Constant::CompletionItemKind::CONSTANT
            detail = item.type.to_s
          end
          LanguageServer::Protocol::Interface::CompletionItem.new(
            label: item.identifier,
            kind: kind,
            detail: detail,
            documentation: format_comments(item.comments),
            text_edit: LanguageServer::Protocol::Interface::TextEdit.new(
              range: range,
              new_text: item.identifier
            )
          )
        when Services::CompletionProvider::MethodNameItem
          method_type_snippet = method_type_to_snippet(item.method_type)
          LanguageServer::Protocol::Interface::CompletionItem.new(
            label: item.identifier,
            kind: LanguageServer::Protocol::Constant::CompletionItemKind::METHOD,
            detail: item.method_type.to_s,
            text_edit: LanguageServer::Protocol::Interface::TextEdit.new(
              new_text: "#{item.identifier}#{method_type_snippet}",
              range: range
            ),
            documentation: format_comment(item.comment),
            insert_text_format: LanguageServer::Protocol::Constant::InsertTextFormat::SNIPPET,
            sort_text: item.inherited? ? 'z' : 'a' # Ensure language server puts non-inherited methods before inherited methods
          )
        when Services::CompletionProvider::InstanceVariableItem
          LanguageServer::Protocol::Interface::CompletionItem.new(
            label: item.identifier,
            kind: LanguageServer::Protocol::Constant::CompletionItemKind::FIELD,
            detail: item.type.to_s,
            text_edit: LanguageServer::Protocol::Interface::TextEdit.new(
              range: range,
              new_text: item.identifier,
            ),
            insert_text_format: LanguageServer::Protocol::Constant::InsertTextFormat::SNIPPET
          )
        end
      end

      def method_type_to_snippet(method_type)
        params = if method_type.type.each_param.count == 0
                   ""
                 else
                   "(#{params_to_snippet(method_type.type)})"
                 end


        block = if method_type.block
                  open, space, close = if method_type.block.type.return_type.is_a?(RBS::Types::Bases::Void)
                                         ["do", " ", "end"]
                                       else
                                         ["{", "", "}"]
                                       end

                  if method_type.block.type.each_param.count == 0
                    " #{open} $0 #{close}"
                  else
                    " #{open}#{space}|#{params_to_snippet(method_type.block.type)}| $0 #{close}"
                  end
                else
                  ""
                end

        "#{params}#{block}"
      end

      def params_to_snippet(fun)
        params = []

        index = 1

        fun.required_positionals.each do |param|
          if name = param.name
            params << "${#{index}:#{param.type}}"
          else
            params << "${#{index}:#{param.type}}"
          end

          index += 1
        end

        if fun.rest_positionals
          params << "${#{index}:*#{fun.rest_positionals.type}}"
          index += 1
        end

        fun.trailing_positionals.each do |param|
          if name = param.name
            params << "${#{index}:#{param.type}}"
          else
            params << "${#{index}:#{param.type}}"
          end

          index += 1
        end

        fun.required_keywords.each do |keyword, param|
          if name = param.name
            params << "#{keyword}: ${#{index}:#{name}_}"
          else
            params << "#{keyword}: ${#{index}:#{param.type}_}"
          end

          index += 1
        end

        params.join(", ")
      end

      def relative_name_in_context(type_name, context)
        context.each do |namespace|
          if (type_name.to_s == namespace.to_type_name.to_s || type_name.namespace.to_s == "::")
            return RBS::TypeName.new(namespace: RBS::Namespace.empty, name: type_name.name)
          elsif type_name.to_s.start_with?(namespace.to_s)
            return TypeName(type_name.to_s.sub(namespace.to_type_name.to_s, '')).relative!
          end
        end
        type_name
      end
    end
  end
end
