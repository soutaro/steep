module Steep
  module Drivers
    class Query
      LSP = LanguageServer::Protocol

      attr_reader :stdout
      attr_reader :stderr

      def initialize(stdout:, stderr:)
        @stdout = stdout
        @stderr = stderr
      end

      # @rbs locations: Array[[String, Integer, Integer]] -- array of [path, line, column]
      # @rbs return: Integer
      def run_hover(locations:)
        unless Daemon.running?
          stderr.puts "Error: Steep server is not running. Start it with `steep server start` or `steep langserver`."
          return 1
        end

        locations.each do |path, line, column|
          absolute_path = to_absolute_path(path)
          unless absolute_path
            stdout.puts JSON.generate({ file: path, line: line, column: column, error: "File not found: #{path}" })
            next
          end

          uri = PathHelper.to_uri(absolute_path).to_s

          request = {
            id: SecureRandom.uuid,
            method: "textDocument/hover",
            params: {
              textDocument: { uri: uri },
              position: { line: line - 1, character: column - 1 }
            }
          }

          result = send_request(request)
          stdout.puts JSON.generate({ file: path, line: line, column: column, result: result })
        end

        0
      rescue Errno::ECONNREFUSED, Errno::ENOENT => e
        stderr.puts "Error: Failed to connect to Steep daemon: #{e.message}"
        1
      end

      # @rbs names: Array[String]
      # @rbs return: Integer
      def run_definition(names:)
        unless Daemon.running?
          stderr.puts "Error: Steep server is not running. Start it with `steep server start` or `steep langserver`."
          return 1
        end

        names.each do |name|
          request = {
            id: SecureRandom.uuid,
            method: Server::CustomMethods::Query__Definition::METHOD,
            params: { name: name }
          }

          result = send_request(request)
          stdout.puts JSON.generate({ name: name, result: result })
        end

        0
      rescue Errno::ECONNREFUSED, Errno::ENOENT => e
        stderr.puts "Error: Failed to connect to Steep daemon: #{e.message}"
        1
      end

      # @rbs paths: Array[String] -- files to query, or empty for all files the server knows about
      # @rbs return: Integer
      def run_diagnostics(paths:)
        unless Daemon.running?
          stderr.puts "Error: Steep server is not running. Start it with `steep server start` or `steep langserver`."
          return 1
        end

        absolute_paths = [] #: Array[Pathname]
        paths.each do |path|
          pathname = Pathname(path)
          pathname = Pathname.pwd + pathname unless pathname.absolute?
          absolute_paths << pathname
        end

        request = {
          id: SecureRandom.uuid,
          method: Server::CustomMethods::Query__Diagnostics::METHOD,
          params: { paths: absolute_paths.empty? ? nil : absolute_paths.map(&:to_s) }
        }

        result = send_request(request) #: Array[{ uri: String, diagnostics: Array[untyped]? }]?

        (result || []).each do |entry|
          path = PathHelper.to_pathname(entry[:uri]) || Pathname(entry[:uri])
          begin
            path = path.relative_path_from(Pathname.pwd)
          rescue ArgumentError
            # Keep the absolute path of files outside of the current directory
          end

          stdout.puts JSON.generate({ path: path.to_s, diagnostics: entry[:diagnostics] })
        end

        0
      rescue Errno::ECONNREFUSED, Errno::ENOENT => e
        stderr.puts "Error: Failed to connect to Steep server: #{e.message}"
        1
      end

      private

      def to_absolute_path(path)
        pathname = Pathname(path)
        pathname = Pathname.pwd + pathname unless pathname.absolute?
        pathname.file? ? pathname : nil
      end

      def send_request(request)
        socket = UNIXSocket.new(Daemon.socket_path)
        reader = LSP::Transport::Io::Reader.new(socket)
        writer = LSP::Transport::Io::Writer.new(socket)

        writer.write(request)

        result = nil #: untyped
        reader.read do |message|
          result = message[:result]
          break
        end

        result
      ensure
        socket&.close
      end
    end
  end
end
