class LSPClient
  # @rbs!
  #   type message = Hash[Symbol, untyped]

  # @rbs @next_request_id: Integer
  # @rbs @incoming_thread: Thread

  attr_reader :reader #: LanguageServer::Protocol::Transport::Io::Reader

  attr_reader :writer #: LanguageServer::Protocol::Transport::Io::Writer

  attr_reader :current_dir #: Pathname

  attr_reader :notifications #: Array[message]

  attr_accessor :default_timeout #: Integer

  attr_reader :request_response_table #: Hash[Integer, message]

  attr_reader :diagnostics #: Hash[Pathname, Array[Hash[Symbol, untyped]]]

  attr_reader :open_files #: Hash[String, String]

  # @rbs reader: LanguageServer::Protocol::Transport::Io::Reader
  # @rbs writer: LanguageServer::Protocol::Transport::Io::Writer
  # @rbs current_dir: Pathname
  # @rbs return: void
  def initialize(reader:, writer:, current_dir:)
    @reader = reader
    @writer = writer
    @current_dir = current_dir

    @default_timeout = TestHelper.timeout
    @next_request_id = 0

    @request_response_table = {}
    @notifications = []

    @diagnostics = {}
    @open_files = {}

    @incoming_thread = Thread.new do
      reader.read do |message|
        case
        when message.key?(:method) && !message.key?(:id)
          # Notification from server
          notifications << message
          case message.fetch(:method)
          when "textDocument/publishDiagnostics"
            path = Steep::PathHelper.to_pathname(message[:params][:uri]) or raise
            path = path.relative_path_from(current_dir)
            diagnostics[path] = message[:params][:diagnostics]
          else
            pp "Unknown notification from server" => message.inspect
          end
        when message.key?(:method) && message.key?(:id)
          # Request from server
          pp "Request from server: #{message.inspect}"
        when !message.key?(:method) && message.key?(:id)
          # Response from server
          request_response_table[message[:id]] = message
        end
      end
    end
  end

  # @rbs id: Integer
  # @rbs timeout: untyped
  # @rbs return: Hash[Symbol, untyped]?
  def get_response(id, timeout: default_timeout)
    finally do
      if request_response_table.key?(id)
        return request_response_table.delete(id) || raise
      end
    end
    nil
  end

  def flush_notifications() #: void
    nots = notifications.dup
    notifications.clear()
    nots
  end

  def join #: void
    @incoming_thread.join
  end

  # @rbs (?timeout: Integer) { () -> void } -> void
  def finally(timeout: default_timeout)
    started_at = Time.now
    while Time.now < started_at + timeout
      yield
      sleep 0.1
    end

    raise "timeout exceeded: #{timeout} seconds"
  end

  # @rbs [T] (?id: Integer, method: String, params: message?) { (untyped) -> T } -> T
  #    | (?id: Integer, method: String, params: message?) -> Integer
  def send_request(id: fresh_request_id, method:, params:, &block)
    writer.write({ id: id, method: method, params: params })

    if block
      yield get_response(id)
    else
      id
    end
  end

  # @rbs (method: String, params: untyped) -> void
  def send_notification(method:, params:)
    writer.write({ method: method, params: params })
  end

  # @rbs (String) -> String
  def uri(path)
    prefix = Gem.win_platform? ? "file:///" : "file://"
    "#{prefix}#{current_dir + path}"
  end

  # @rbs *paths: String
  def open_file(*paths) #: void
    paths.each do |path|
      content = (current_dir + path).read
      open_files[path] = content
      send_notification(
        method: "textDocument/didOpen",
        params: {
          textDocument: { uri: uri(path), text: content }
        }
      )
    end
  end

  # @rbs *paths: String
  def close_file(*paths)
    paths.each do |path|
      send_notification(
        method: "textDocument/didClose",
        params: {
          textDocument: {
            uri: uri(path)
          }
        }
      )
    end
  end

  # @rbs (String) { (String?) -> String } -> void
  def change_file(path)
    content = open_files[path]
    content = open_files[path] = yield(content)

    send_notification(
      method: "textDocument/didChange",
      params: {
        textDocument: {
          uri: uri(path),
          version: (Time.now.to_f * 1000).to_i
        },
        contentChanges: [{ text: content }]
      }
    )
  end

  # @rbs (String) -> void
  def save_file(path)
    content = open_files.delete(path) or raise
    (current_dir + path).write(content)

    send_notification(
      method: "textDocument/didSave",
      params: {
        textDocument: {
          uri: uri(path),
          text: content
        }
      }
    )
    change_watched_file(path)
  end

  # @rbs *path: String
  def change_watched_file(*paths) #: void
    changes = [] #: Array[message]
    paths.each do |path|
      path = current_dir + path

      if path.file?
        # Created (or maybe modified)
        changes << { uri: uri(path), type: 1 }
      else
        # Deleted
        changes << { uri: uri(path), type: 4 }
      end
    end

    send_notification(
      method: "workspace/didChangeWatchedFiles",
      params: { changes: changes }
    )
  end

  # @rbs (?String query) { (untyped) -> void } -> void
  def workspace_symbol(query = "", &block)
    send_request(
      method: "workspace/symbol",
      params: { query: query },
    ) do |response|
      yield response[:result]
    end
  end

  # @rbs (String path, line: Integer, character: Integer) { (untyped) -> void } -> void
  def goto_definition(path, line:, character:, &block)
    send_request(
      method: "textDocument/definition",
      params: {
        textDocument: { uri: uri(path) },
        position: { line: line, character: character }
      }
    ) do |response|
      yield response[:result]
    end
  end

  # @rbs (String path, line: Integer, character: Integer) { (untyped) -> void } -> void
  def goto_implementation(path, line:, character:, &block)
    send_request(
      method: "textDocument/implementation",
      params: {
        textDocument: { uri: uri(path) },
        position: { line: line, character: character }
      }
    ) do |response|
      yield response[:result]
    end
  end

  protected

  def fresh_request_id #: Integer
    @next_request_id += 1
  end
end
