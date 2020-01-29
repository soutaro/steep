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
                )
            )

            enqueue_type_check nil
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
              run_type_check()
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
                  diagnostics = source.errors.map {|error| diagnostic_for_type_error(error) }
                  report_diagnostics source.path, diagnostics
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

        # line in LSP is zero-origin
        project.type_of_node(path: path, line: line + 1, column: column) do |type, node|
          Steep.logger.warn { "node = #{node.type}, type = #{type.to_s}" }

          start_position = { line: node.location.line - 1, character: node.location.column }
          end_position = { line: node.location.last_line - 1, character: node.location.last_column }
          range = { start: start_position, end: end_position }

          Steep.logger.warn { "range = #{range.inspect}" }

          LanguageServer::Protocol::Interface::Hover.new(
            contents: { kind: "markdown", value: "`#{type}`" },
            range: range
          )
        end
      end
    end
  end
end
