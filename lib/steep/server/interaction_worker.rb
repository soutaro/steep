module Steep
  module Server
    class InteractionWorker < BaseWorker
      include ChangeBuffer

      ApplyChangeJob = _ = Class.new()
      HoverJob = _ = Struct.new(:id, :path, :line, :column, keyword_init: true)
      CompletionJob = _ = Struct.new(:id, :path, :line, :column, :trigger, keyword_init: true)

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

          path = project.relative_path(Steep::PathHelper.to_pathname!(request[:params][:textDocument][:uri]))
          line = request[:params][:position][:line]+1
          column = request[:params][:position][:character]

          queue << HoverJob.new(id: id, path: path, line: line, column: column)

        when "textDocument/completion"
          id = request[:id]

          params = request[:params]

          path = project.relative_path(Steep::PathHelper.to_pathname!(params[:textDocument][:uri]))
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
            when (targets = project.targets_for_path(job.path)).is_a?(Array)
              target = targets[0] or raise
              sig_service = service.signature_services[target.name] or raise
              relative_path = job.path

              context = nil #: RBS::Resolver::context

              case sig_service.status
              when Steep::Services::SignatureService::SyntaxErrorStatus, Steep::Services::SignatureService::AncestorErrorStatus

                if buffer = sig_service.latest_env.buffers.find {|buf| Pathname(buf.name) == Pathname(relative_path) }
                  dirs = sig_service.latest_env.signatures[buffer][0]
                else
                  dirs = [] #: Array[RBS::AST::Directives::t]
                end
              else
                signature = sig_service.files[relative_path].signature
                signature.is_a?(Array) or raise
                buffer, dirs, decls = signature

                locator = RBS::Locator.new(buffer: buffer, dirs: dirs, decls: decls)

                _hd, tail = locator.find2(line: job.line, column: job.column)
                tail ||= []

                tail.reverse_each do |t|
                  case t
                  when RBS::AST::Declarations::Module, RBS::AST::Declarations::Class
                    if (last_type_name = context&.[](1)).is_a?(RBS::TypeName)
                      context = [context, last_type_name + t.name]
                    else
                      context = [context, t.name.absolute!]
                    end
                  end
                end
              end

              buffer = RBS::Buffer.new(name: relative_path, content: sig_service.files[relative_path].content)
              prefix = Services::TypeNameCompletion::Prefix.parse(buffer, line: job.line, column: job.column)

              completion = Services::TypeNameCompletion.new(env: sig_service.latest_env, context: context, dirs: dirs)
              type_names = completion.find_type_names(prefix)
              prefix_size = prefix ? prefix.size : 0

              completion_items = type_names.map do |type_name|
                absolute_name, relative_name = completion.resolve_name_in_context(type_name)
                format_completion_item_for_rbs(sig_service, absolute_name, job, relative_name.to_s, prefix_size)
              end

              ["untyped", "void", "bool", "class", "module", "instance", "nil"].each do |name|
                completion_items << LanguageServer::Protocol::Interface::CompletionItem.new(
                  label: name,
                  detail: "(builtin type)",
                  text_edit: LanguageServer::Protocol::Interface::TextEdit.new(
                    range: LanguageServer::Protocol::Interface::Range.new(
                      start: LanguageServer::Protocol::Interface::Position.new(
                        line: job.line - 1,
                        character: job.column - prefix_size
                      ),
                      end: LanguageServer::Protocol::Interface::Position.new(
                        line: job.line - 1,
                        character: job.column
                      )
                    ),
                    new_text: name
                  ),
                  kind: LSP::Constant::CompletionItemKind::KEYWORD,
                  filter_text: name,
                  sort_text: "zz__#{name}"
                )
              end

              LSP::Interface::CompletionList.new(
                is_incomplete: false,
                items: completion_items
              )
            end
          end
        end
      end

      def format_completion_item_for_rbs(sig_service, type_name, job, complete_text, prefix_size)
        range = LanguageServer::Protocol::Interface::Range.new(
          start: LanguageServer::Protocol::Interface::Position.new(
            line: job.line - 1,
            character: job.column - prefix_size
          ),
          end: LanguageServer::Protocol::Interface::Position.new(
            line: job.line - 1,
            character: job.column
          )
        )

        case type_name.kind
        when :class
          env = sig_service.latest_env #: RBS::Environment
          class_entry = env.module_class_entry(type_name) or raise

          comment =
            case class_entry
            when RBS::Environment::ClassEntry, RBS::Environment::ModuleEntry
              class_entry.decls.flat_map {|decl| [decl.decl.comment] }.first
            when RBS::Environment::ClassAliasEntry, RBS::Environment::ModuleAliasEntry
              class_entry.decl.comment
            end

          LanguageServer::Protocol::Interface::CompletionItem.new(
            label: complete_text,
            detail: type_name.to_s,
            documentation:  format_comment(comment),
            text_edit: LanguageServer::Protocol::Interface::TextEdit.new(
              range: range,
              new_text: complete_text
            ),
            kind: LSP::Constant::CompletionItemKind::CLASS,
            insert_text_format: LSP::Constant::InsertTextFormat::SNIPPET,
            sort_text: complete_text,
            filter_text: complete_text
          )
        when :alias
          alias_decl = sig_service.latest_env.type_alias_decls[type_name]&.decl or raise

          LanguageServer::Protocol::Interface::CompletionItem.new(
            label: complete_text,
            detail: type_name.to_s,
            text_edit: LanguageServer::Protocol::Interface::TextEdit.new(
              range: range,
              new_text: complete_text
            ),
            documentation: format_comment(alias_decl.comment),
            # https://github.com/microsoft/vscode-languageserver-node/blob/6d78fc4d25719b231aba64a721a606f58b9e0a5f/client/src/common/client.ts#L624-L650
            kind: LSP::Constant::CompletionItemKind::FIELD,
            insert_text_format: LSP::Constant::InsertTextFormat::SNIPPET,
            sort_text: complete_text,
            filter_text: complete_text
          )
        when :interface
          interface_decl = sig_service.latest_env.interface_decls[type_name]&.decl or raise

          LanguageServer::Protocol::Interface::CompletionItem.new(
            label: complete_text,
            detail: type_name.to_s,
            text_edit: LanguageServer::Protocol::Interface::TextEdit.new(
              range: range,
              new_text: complete_text
            ),
            documentation: format_comment(interface_decl.comment),
            kind: LanguageServer::Protocol::Constant::CompletionItemKind::INTERFACE,
            insert_text_format: LanguageServer::Protocol::Constant::InsertTextFormat::SNIPPET,
            sort_text: complete_text,
            filter_text: complete_text
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
    end
  end
end
