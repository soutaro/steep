module Steep
  module Server
    class InteractionWorker < BaseWorker
      attr_reader :queue

      def initialize(project:, reader:, writer:, queue: Queue.new)
        super(project: project, reader: reader, writer: writer)
        @queue = queue
      end

      def handle_job(job)
        Steep.logger.debug "Handling job: id=#{job[:id]}, result=#{job[:result]&.to_hash}"
        writer.write(job)
      end

      def handle_request(request)
        case request[:method]
        when "initialize"
          # nop

        when "textDocument/didChange"
          update_source(request)

        when "textDocument/hover"
          id = request[:id]

          uri = URI.parse(request[:params][:textDocument][:uri])
          path = project.relative_path(Pathname(uri.path))
          line = request[:params][:position][:line]
          column = request[:params][:position][:character]

          queue << {
            id: id,
            result: response_to_hover(path: path, line: line, column: column)
          }

        when "textDocument/completion"
          id = request[:id]

          params = request[:params]
          uri = URI.parse(params[:textDocument][:uri])
          path = project.relative_path(Pathname(uri.path))
          line, column = params[:position].yield_self {|hash| [hash[:line]+1, hash[:character]] }
          trigger = params[:context][:triggerCharacter]

          queue << {
            id: id,
            result: response_to_completion(path: path, line: line, column: column, trigger: trigger)
          }
        end
      end

      def response_to_hover(path:, line:, column:)
        Steep.logger.tagged "#response_to_hover" do
          Steep.logger.debug { "path=#{path}, line=#{line}, column=#{column}" }

          hover = Project::HoverContent.new(project: project)
          content = hover.content_for(path: path, line: line+1, column: column+1)
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

      def format_hover(content)
        case content
        when Project::HoverContent::VariableContent
          "`#{content.name}`: `#{content.type.to_s}`"
        when Project::HoverContent::MethodCallContent
          method_name = case content.method_name
                        when Project::HoverContent::InstanceMethodName
                          "#{content.method_name.class_name}##{content.method_name.method_name}"
                        when Project::HoverContent::SingletonMethodName
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
              if content.definition.comment
                string << "\n----\n\n#{content.definition.comment.string}"
              end

              string << "\n----\n\n#{content.definition.method_types.map {|x| "- `#{x}`\n" }.join()}"
            end
          else
            "`#{content.type}`"
          end
        when Project::HoverContent::DefinitionContent
          string = <<HOVER
```
def #{content.method_name}: #{content.method_type}
```
HOVER
          if (comment = content.definition.comment)
            string << "\n----\n\n#{comment.string}\n"
          end

          if content.definition.method_types.size > 1
            string << "\n----\n\n#{content.definition.method_types.map {|x| "- `#{x}`\n" }.join()}"
          end

          string
        when Project::HoverContent::TypeContent
          "`#{content.type}`"
        end
      end

      def response_to_completion(path:, line:, column:, trigger:)
        Steep.logger.tagged("#response_to_completion") do
          Steep.logger.info "path: #{path}, line: #{line}, column: #{column}, trigger: #{trigger}"

          target = project.targets.find {|target| target.source_file?(path) } or return
          target.type_check(target_sources: [], validate_signatures: false)

          case (status = target&.status)
          when Project::Target::TypeCheckStatus
            subtyping = status.subtyping
            source = target.source_files[path]

            provider = Project::CompletionProvider.new(source_text: source.content, path: path, subtyping: subtyping)
            items = begin
                      provider.run(line: line, column: column)
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
        when Project::CompletionProvider::LocalVariableItem
          LanguageServer::Protocol::Interface::CompletionItem.new(
            label: item.identifier,
            kind: LanguageServer::Protocol::Constant::CompletionItemKind::VARIABLE,
            detail: "#{item.identifier}: #{item.type}",
            text_edit: LanguageServer::Protocol::Interface::TextEdit.new(
              range: range,
              new_text: "#{item.identifier}"
            )
          )
        when Project::CompletionProvider::MethodNameItem
          label = "def #{item.identifier}: #{item.method_type}"
          method_type_snippet = method_type_to_snippet(item.method_type)
          LanguageServer::Protocol::Interface::CompletionItem.new(
            label: label,
            kind: LanguageServer::Protocol::Constant::CompletionItemKind::METHOD,
            text_edit: LanguageServer::Protocol::Interface::TextEdit.new(
              new_text: "#{item.identifier}#{method_type_snippet}",
              range: range
            ),
            documentation: item.definition.comment&.string,
            insert_text_format: LanguageServer::Protocol::Constant::InsertTextFormat::SNIPPET,
            sort_text: item.inherited_method ? 'z' : 'a' # Ensure language server puts non-inherited methods before inherited methods
          )
        when Project::CompletionProvider::InstanceVariableItem
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
