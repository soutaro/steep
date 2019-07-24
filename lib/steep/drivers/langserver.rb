module Steep
  module Drivers
    class Langserver
      attr_reader :source_dirs
      attr_reader :signature_options
      attr_reader :options
      attr_reader :subscribers
      attr_reader :open_paths

      include Utils::EachSignature

      def initialize(source_dirs:, signature_options:)
        @source_dirs = source_dirs
        @signature_options = signature_options
        @options = Project::Options.new
        @subscribers = {}
        @open_paths = Set.new

        subscribe :initialize do |request:, notifier:|
          LanguageServer::Protocol::Interface::InitializeResult.new(
            capabilities: LanguageServer::Protocol::Interface::ServerCapabilities.new(
              text_document_sync: LanguageServer::Protocol::Interface::TextDocumentSyncOptions.new(
                open_close: true,
                change: LanguageServer::Protocol::Constant::TextDocumentSyncKind::FULL,
              ),
              hover_provider: true
            ),
          )
        end

        subscribe :shutdown do |request:, notifier:|
          Steep.logger.warn "Shutting down the server..."
          exit
        end

        subscribe :"textDocument/didOpen" do |request:, notifier:|
          uri = URI.parse(request[:params][:textDocument][:uri])
          open_path uri
          text = request[:params][:textDocument][:text]
          synchronize_project(uri: uri, text: text, notifier: notifier)
        end

        subscribe :"textDocument/didClose" do |request:, notifier:|
          uri = URI.parse(request[:params][:textDocument][:uri])
          close_path uri
        end

        subscribe :"textDocument/didChange" do |request:, notifier:|
          uri = URI.parse(request[:params][:textDocument][:uri])
          text = request[:params][:contentChanges][0][:text]
          synchronize_project(uri: uri, text: text, notifier: notifier)
        end

        subscribe :"textDocument/hover" do |request:, notifier:|
          Steep.logger.warn request.inspect
          uri = URI.parse(request[:params][:textDocument][:uri])
          line = request[:params][:position][:line]
          column = request[:params][:position][:character]
          respond_to_hover(uri: uri, line: line, column: column, notifier: notifier, id: request[:id])
        end
      end

      def respond_to_hover(uri:, line:, column:, notifier:, id:)
        path = Pathname(uri.path).relative_path_from(Pathname.pwd)

        if path.extname == ".rb"
          # line in LSP is zero-origin
          project.type_of(path: path, line: line + 1, column: column) do |type, node|
            Steep.logger.warn "type = #{type.to_s}"

            start_position = { line: node.location.line - 1, character: node.location.column }
            end_position = { line: node.location.last_line - 1, character: node.location.last_column }
            range = { start: start_position, end: end_position }

            Steep.logger.warn "node = #{node.type}"
            Steep.logger.warn "range = #{range.inspect}"

            LanguageServer::Protocol::Interface::Hover.new(
              contents: { kind: "markdown", value: "`#{type}`" },
              range: range
            )
          end
        end
      end

      def subscribe(method, &callback)
        @subscribers[method] = callback
      end

      def project
        @project ||= begin
          loader = Ruby::Signature::EnvironmentLoader.new()
          loader.stdlib_root = nil if signature_options.no_builtin
          signature_options.library_paths.each do |path|
            loader.add(path: path)
          end

          environment = Ruby::Signature::Environment.new()
          loader.load(env: environment)

          Project.new(environment: environment).tap do |project|
            source_dirs.each do |path|
              each_file_in_path(".rb", path) do |file_path|
                file = Project::SourceFile.new(path: file_path, options: options)
                file.content = file_path.read
                project.source_files[file_path] = file
              end
            end

            signature_options.signature_paths.each do |path|
              each_file_in_path(".rbi", path) do |file_path|
                file = Project::SignatureFile.new(path: file_path)
                file.content = file_path.read
                project.signature_files[file_path] = file
              end
            end
          end
        end
      end

      def open_path?(path)
        open_paths.member?(path)
      end

      def open_path(path)
        open_paths << path
      end

      def close_path(path)
        open_paths.delete path
      end

      def run
        writer = LanguageServer::Protocol::Transport::Stdio::Writer.new
        reader = LanguageServer::Protocol::Transport::Stdio::Reader.new
        notifier = Proc.new { |method:, params: {}| writer.write(method: method, params: params) }

        reader.read do |request|
          id = request[:id]
          method = request[:method].to_sym
          Steep.logger.warn "Received event: #{method}"
          subscriber = subscribers[method]
          if subscriber
            result = subscriber.call(request: request, notifier: notifier)
            if id && result
              writer.write(id: id, result: result)
            end
          else
            Steep.logger.warn "Ignored event: #{method}"
          end
        end
      end

      def synchronize_project(uri:, text:, notifier:)
        # path = Pathname(uri.path).relative_path_from(Pathname.pwd)
        path = Pathname(uri.path)

        case path.extname
        when ".rb"
          file = project.source_files[path] || Project::SourceFile.new(path: path, options: options)
          file.content = text
          project.source_files[path] = file
        when ".rbi"
          file = project.signature_files[path] || Project::SignatureFile.new(path: path)
          file.content = text
          project.signature_files[path] = file
        end

        project.type_check

        open_paths.each do |uri|
          Pathname(uri.path).yield_self do |path|
          # Pathname(uri.path).relative_path_from(Pathname.pwd).yield_self do |path|
            case path.extname
            when ".rb"
              file = project.source_files[path] || Project::SourceFile.new(path: path, options: options)
              diags = (file.errors || []).map do |error|
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

              notifier.call(
                method: :"textDocument/publishDiagnostics",
                params: LanguageServer::Protocol::Interface::PublishDiagnosticsParams.new(
                  uri: uri,
                  diagnostics: diags,
                  ),
                )
            end
          end
        end
      end
    end
  end
end
