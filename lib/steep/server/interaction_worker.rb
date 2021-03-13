module Steep
  module Server
    class InteractionWorker < BaseWorker
      include ChangeBuffer

      ApplyChangeJob = Class.new()
      HoverJob = Struct.new(:id, :path, :line, :column, keyword_init: true)
      CompletionJob = Struct.new(:id, :path, :line, :column, :trigger, keyword_init: true)

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

          uri = URI.parse(request[:params][:textDocument][:uri])
          path = project.relative_path(Pathname(uri.path))
          line = request[:params][:position][:line]+1
          column = request[:params][:position][:character]

          queue << HoverJob.new(id: id, path: path, line: line, column: column)

        when "textDocument/completion"
          id = request[:id]

          params = request[:params]
          uri = URI.parse(params[:textDocument][:uri])
          path = project.relative_path(Pathname(uri.path))
          line, column = params[:position].yield_self {|hash| [hash[:line]+1, hash[:character]] }
          trigger = params[:context][:triggerCharacter]

          queue << CompletionJob.new(id: id, path: path, line: line, column: column, trigger: trigger)
        end
      end

      def process_hover(job)
        Steep.logger.tagged "#process_hover" do
          Steep.measure "Generating hover response" do
            Steep.logger.info { "path=#{job.path}, line=#{job.line}, column=#{job.column}" }

            hover = Services::HoverContent.new(service: service)
            content = hover.content_for(path: job.path, line: job.line, column: job.column+1)
            if content
              range = content.location.yield_self do |location|
                start_position = { line: location.line - 1, character: location.column }
                end_position = { line: location.last_line - 1, character: location.last_column }
                { start: start_position, end: end_position }
              end

              LSP::Interface::Hover.new(
                contents: { kind: "markdown", value: format_hover(content) },
                range: range
              )
            end
          rescue Typing::UnknownNodeError => exn
            Steep.log_error exn, message: "Failed to compute hover: #{exn.inspect}"
            nil
          end
        end
      end

      def format_hover(content)
        case content
        when Services::HoverContent::VariableContent
          "`#{content.name}`: `#{content.type.to_s}`"
        when Services::HoverContent::MethodCallContent
          method_name = case content.method_name
                        when Services::HoverContent::InstanceMethodName
                          "#{content.method_name.class_name}##{content.method_name.method_name}"
                        when Services::HoverContent::SingletonMethodName
                          "#{content.method_name.class_name}.#{content.method_name.method_name}"
                        else
                          nil
                        end

          if method_name
            string = <<HOVER
```
#{method_name} ~> #{content.type}
```
HOVER
            if content.definition
              if content.definition.comments
                string << "\n----\n\n#{content.definition.comments.map(&:string).join("\n\n")}"
              end

              string << "\n----\n\n#{content.definition.method_types.map {|x| "- `#{x}`\n" }.join()}"
            end
          else
            "`#{content.type}`"
          end
        when Services::HoverContent::DefinitionContent
          string = <<HOVER
```
def #{content.method_name}: #{content.method_type}
```
HOVER
          if (comment = content.comment_string)
            string << "\n----\n\n#{comment}\n"
          end

          if content.definition.method_types.size > 1
            string << "\n----\n\n#{content.definition.method_types.map {|x| "- `#{x}`\n" }.join()}"
          end

          string
        when Services::HoverContent::TypeContent
          "`#{content.type}`"
        end
      end

      def process_completion(job)
        Steep.logger.tagged("#response_to_completion") do
          Steep.measure "Generating response" do
            Steep.logger.info "path: #{job.path}, line: #{job.line}, column: #{job.column}, trigger: #{job.trigger}"

            target = project.target_for_source_path(job.path) or return
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
          end
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
            detail: "#{item.identifier}: #{item.type}",
            text_edit: LanguageServer::Protocol::Interface::TextEdit.new(
              range: range,
              new_text: "#{item.identifier}"
            )
          )
        when Services::CompletionProvider::MethodNameItem
          label = "def #{item.identifier}: #{item.method_type}"
          method_type_snippet = method_type_to_snippet(item.method_type)
          LanguageServer::Protocol::Interface::CompletionItem.new(
            label: label,
            kind: LanguageServer::Protocol::Constant::CompletionItemKind::METHOD,
            text_edit: LanguageServer::Protocol::Interface::TextEdit.new(
              new_text: "#{item.identifier}#{method_type_snippet}",
              range: range
            ),
            documentation: item.comment&.string,
            insert_text_format: LanguageServer::Protocol::Constant::InsertTextFormat::SNIPPET,
            sort_text: item.inherited? ? 'z' : 'a' # Ensure language server puts non-inherited methods before inherited methods
          )
        when Services::CompletionProvider::InstanceVariableItem
          label = "#{item.identifier}: #{item.type}"
          LanguageServer::Protocol::Interface::CompletionItem.new(
            label: label,
            kind: LanguageServer::Protocol::Constant::CompletionItemKind::FIELD,
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
