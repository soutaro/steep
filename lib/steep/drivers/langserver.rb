module Steep
  module Drivers
    class Langserver
      attr_reader :stdout
      attr_reader :stderr
      attr_reader :stdin
      attr_reader :latest_update_version
      attr_reader :write_mutex
      attr_reader :type_check_queue
      attr_reader :type_check_thread

      include Utils::DriverHelper

      TypeCheckRequest = Struct.new(:version, keyword_init: true)

      def initialize(stdout:, stderr:, stdin:)
        @stdout = stdout
        @stderr = stderr
        @stdin = stdin
        @write_mutex = Mutex.new
        @type_check_queue = Queue.new
      end

      def writer
        @writer ||= LanguageServer::Protocol::Transport::Io::Writer.new(stdout)
      end

      def reader
        @reader ||= LanguageServer::Protocol::Transport::Io::Reader.new(stdin)
      end

      def project
        @project or raise "Empty #project"
      end

      def enqueue_type_check(version)
        @latest_update_version = version
        type_check_queue << TypeCheckRequest.new(version: version)
      end

      def run
        @project = load_config()

        loader = Project::FileLoader.new(project: project)
        loader.load_sources([])
        loader.load_signatures()

        start_type_check()

        reader.read do |request|
          Steep.logger.tagged "lsp" do
            Steep.logger.debug { "Received a request: request=#{request.to_json}" }
            handle_request(request) do |id, result|
              if id
                write_mutex.synchronize do
                  Steep.logger.debug { "Writing response to #{id}: #{result.to_json}" }
                  writer.write(id: id, result: result)
                end
              end
            end
          end
        end

        0
      end

      def write(method:, params:)
        write_mutex.synchronize do
          Steep.logger.debug { "Sending request: method=#{method}, params=#{params.to_json}"}
          writer.write(method: method, params: params)
        end
      end

      def handle_request(request)
        id = request[:id]
        method = request[:method].to_sym

        Steep.logger.tagged "id=#{id}, method=#{method}" do
          case method
          when :initialize
            yield id, LanguageServer::Protocol::Interface::InitializeResult.new(
              capabilities: LanguageServer::Protocol::Interface::ServerCapabilities.new(
                text_document_sync: LanguageServer::Protocol::Interface::TextDocumentSyncOptions.new(
                  change: LanguageServer::Protocol::Constant::TextDocumentSyncKind::FULL
                ),
                hover_provider: true,
                completion_provider: LanguageServer::Protocol::Interface::CompletionOptions.new(
                  trigger_characters: [".", "@"],
                )
              )
            )

            enqueue_type_check nil

          when :"textDocument/completion"
            Steep.logger.error request.inspect
            begin
              params = request[:params]
              uri = URI.parse(params[:textDocument][:uri])
              path = project.relative_path(Pathname(uri.path))
              target = project.targets.find {|target| target.source_file?(path) }
              case (status = target&.status)
              when Project::Target::TypeCheckStatus
                subtyping = status.subtyping
                source = target.source_files[path]

                line, column = params[:position].yield_self {|hash| [hash[:line]+1, hash[:character]] }
                trigger = params[:context][:triggerCharacter]

                Steep.logger.error "line: #{line}, column: #{column}, trigger: #{trigger}"

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

                yield id, LanguageServer::Protocol::Interface::CompletionList.new(
                  is_incomplete: false,
                  items: completion_items
                )
              end

            rescue Typing::UnknownNodeError => exn
              Steep.log_error exn, message: "Failed to compute completion: #{exn.inspect}"
              yield id, nil
            end

          when :"textDocument/didChange"
            uri = URI.parse(request[:params][:textDocument][:uri])
            path = project.relative_path(Pathname(uri.path))
            text = request[:params][:contentChanges][0][:text]

            Steep.logger.debug { "path=#{path}, content=#{text.lines.first&.chomp}..." }

            project.targets.each do |target|
              Steep.logger.tagged "target=#{target.name}" do
                case
                when target.source_file?(path)
                  if text.empty? && !path.file?
                    Steep.logger.info { "Deleting source file: #{path}..." }
                    target.remove_source(path)
                    report_diagnostics path, []
                  else
                    Steep.logger.info { "Updating source file: #{path}..." }
                    target.update_source(path, text)
                  end
                when target.possible_source_file?(path)
                  Steep.logger.info { "Adding source file: #{path}..." }
                  target.add_source(path, text)
                when target.signature_file?(path)
                  if text.empty? && !path.file?
                    Steep.logger.info { "Deleting signature file: #{path}..." }
                    target.remove_signature(path)
                    report_diagnostics path, []
                  else
                    Steep.logger.info { "Updating signature file: #{path}..." }
                    target.update_signature(path, text)
                  end
                when target.possible_signature_file?(path)
                  Steep.logger.info { "Adding signature file: #{path}..." }
                  target.add_signature(path, text)
                end
              end
            end

            version = request[:params][:textDocument][:version]
            enqueue_type_check version
          when :"textDocument/hover"
            uri = URI.parse(request[:params][:textDocument][:uri])
            path = project.relative_path(Pathname(uri.path))
            line = request[:params][:position][:line]
            column = request[:params][:position][:character]

            yield id, response_to_hover(path: path, line: line, column: column)

          when :shutdown
            yield id, nil

          when :exit
            type_check_queue << nil
            type_check_thread.join
            exit
          end
        end
      end

      def start_type_check
        @type_check_thread = Thread.start do
          while request = type_check_queue.deq
            if @latest_update_version == nil || @latest_update_version == request.version
              begin
                run_type_check()
              rescue => exn
                Steep.log_error exn
              end
            end
          end
        end
      end

      def run_type_check()
        Steep.logger.tagged "#run_type_check" do
          Steep.logger.info { "Running type check..." }
          type_check project

          Steep.logger.info { "Sending diagnostics..." }
          project.targets.each do |target|
            Steep.logger.tagged "target=#{target.name}, status=#{target.status.class}" do
              Steep.logger.info { "Clearing signature diagnostics..." }
              target.signature_files.each_value do |file|
                report_diagnostics file.path, []
              end

              case (status = target.status)
              when Project::Target::SignatureValidationErrorStatus
                Steep.logger.info { "Signature validation error" }
                status.errors.group_by(&:path).each do |path, errors|
                  diagnostics = errors.map {|error| diagnostic_for_validation_error(error) }
                  report_diagnostics path, diagnostics
                end
              when Project::Target::TypeCheckStatus
                Steep.logger.info { "Type check" }
                status.type_check_sources.each do |source|
                  diagnostics = case source.status
                                when Project::SourceFile::TypeCheckStatus
                                  source.errors.map {|error| diagnostic_for_type_error(error) }
                                when Project::SourceFile::AnnotationSyntaxErrorStatus
                                  [diagnostics_raw(source.status.error.message, source.status.location)]
                                when Project::SourceFile::ParseErrorStatus
                                  []
                                when Project::SourceFile::TypeCheckErrorStatus
                                  Steep.log_error source.status.error
                                  []
                                end

                  if diagnostics
                    report_diagnostics source.path, diagnostics
                  end
                end
              when Project::Target::SignatureSyntaxErrorStatus
                Steep.logger.info { "Signature syntax error" }
              end
            end
          end
        end
      end

      def report_diagnostics(path, diagnostics)
        Steep.logger.info { "Reporting #{diagnostics.size} diagnostics for #{path}..." }
        write(
          method: :"textDocument/publishDiagnostics",
          params: LanguageServer::Protocol::Interface::PublishDiagnosticsParams.new(
            uri: URI.parse(project.absolute_path(path).to_s).tap {|uri| uri.scheme = "file"},
            diagnostics: diagnostics,
          )
        )
      end

      def diagnostic_for_validation_error(error)
        LanguageServer::Protocol::Interface::Diagnostic.new(
          message: StringIO.new("").tap {|io| error.puts(io) }.string,
          severity: LanguageServer::Protocol::Constant::DiagnosticSeverity::ERROR,
          range: LanguageServer::Protocol::Interface::Range.new(
            start: LanguageServer::Protocol::Interface::Position.new(
              line: error.location.start_line - 1,
              character: error.location.start_column,
              ),
            end: LanguageServer::Protocol::Interface::Position.new(
              line: error.location.end_line - 1,
              character: error.location.end_column,
              ),
            )
        )
      end

      def diagnostics_raw(message, loc)
        LanguageServer::Protocol::Interface::Diagnostic.new(
          message: message,
          severity: LanguageServer::Protocol::Constant::DiagnosticSeverity::ERROR,
          range: LanguageServer::Protocol::Interface::Range.new(
            start: LanguageServer::Protocol::Interface::Position.new(
              line: loc.start_line - 1,
              character: loc.start_column,
              ),
            end: LanguageServer::Protocol::Interface::Position.new(
              line: loc.end_line - 1,
              character: loc.end_column,
              ),
            )
        )
      end

      def diagnostic_for_type_error(error)
        LanguageServer::Protocol::Interface::Diagnostic.new(
          message: error.to_s,
          severity: LanguageServer::Protocol::Constant::DiagnosticSeverity::ERROR,
          range: LanguageServer::Protocol::Interface::Range.new(
            start: LanguageServer::Protocol::Interface::Position.new(
              line: error.node.loc.line - 1,
              character: error.node.loc.column,
              ),
            end: LanguageServer::Protocol::Interface::Position.new(
              line: error.node.loc.last_line - 1,
              character: error.node.loc.last_column,
              ),
            )
        )
      end

      def response_to_hover(path:, line:, column:)
        Steep.logger.info { "path=#{path}, line=#{line}, column=#{column}" }

        hover = Project::HoverContent.new(project: project)
        content = hover.content_for(path: path, line: line+1, column: column+1)
        if content
          range = content.location.yield_self do |location|
            start_position = { line: location.line - 1, character: location.column }
            end_position = { line: location.last_line - 1, character: location.last_column }
            { start: start_position, end: end_position }
          end

          LanguageServer::Protocol::Interface::Hover.new(
            contents: { kind: "markdown", value: format_hover(content) },
            range: range
          )
        end
      rescue Typing::UnknownNodeError => exn
        Steep.log_error exn, message: "Failed to compute hover: #{exn.inspect}"
        nil
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
            insert_text_format: LanguageServer::Protocol::Constant::InsertTextFormat::SNIPPET
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
