class LSPClient
  attr_reader :reader, :writer, :current_dir

  attr_reader :notifications

  attr_accessor :default_timeout

  attr_reader :request_response_table

  attr_reader :diagnostics

  attr_reader :open_files

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
            path = Steep::PathHelper.to_pathname(message[:params][:uri])
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

  def get_response(id, timeout: default_timeout)
    finally do
      if request_response_table.key?(id)
        return request_response_table.delete(id)
      end
    end
  end

  def flush_notifications()
    nots = notifications.dup
    notifications.clear()
    nots
  end

  def join
    @incoming_thread.join
  end

  def finally(timeout: default_timeout)
    started_at = Time.now
    while Time.now < started_at + timeout
      yield
      sleep 0.1
    end

    raise "timeout exceeded: #{timeout} seconds"
  end

  def send_request(id: fresh_request_id, method:, params:, &block)
    writer.write({ id: id, method: method, params: params })

    if block
      yield get_response(id)
    else
      id
    end
  end

  def send_notification(method:, params:)
    writer.write({ method: method, params: params })
  end

  def uri(path)
    prefix = Gem.win_platform? ? "file:///" : "file://"
    "#{prefix}#{current_dir + path}"
  end

  def open_file(*paths)
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

  def change_watched_file(*paths)
    changes = []
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

  def workspace_symbol(query = "", &block)
    send_request(
      method: "workspace/symbol",
      params: { query: query },
    ) do |response|
      yield response[:result]
    end
  end

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

  def fresh_request_id
    @next_request_id += 1
  end
end
