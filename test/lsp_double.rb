class LSPDouble
  attr_reader :reader
  attr_reader :writer
  attr_reader :diagnostics
  attr_reader :reader_thread
  attr_reader :response_queue

  attr_reader :responses
  attr_reader :mutex

  attr_accessor :default_timeout

  def initialize(reader:, writer:)
    @reader = reader
    @writer = writer

    @next_request_id = 0

    @response_queue = Queue.new
    @diagnostics = {}
    @responses = {}
    @mutex = Mutex.new

    @default_timeout = TestHelper.timeout
  end

  def file_scheme
    if Gem.win_platform?
      "file:///"
    else
      "file://"
    end
  end

  def next_request_id
    @next_request_id += 1
  end

  def start()
    raise if reader_thread

    @reader_thread = Thread.new do
      Steep.logger.tagged "LSP client" do
        reader.read do |event|
          Steep.logger.info "received event: event=#{event}"

          if event.key?(:method)
            process_request event
          else
            process_response event
          end
        end
      end
    end

    send_request(id: next_request_id, method: "initialize", params: {}) { }
    send_notification(method: "initialized", params: {})

    if block_given?
      begin
        yield
      ensure
        stop
      end
    else
      self
    end
  end

  def stop
    send_request(method: "shutdown") {}
    send_notification(method: "exit")
  end

  def process_request(request)
    case request[:method]
    when "textDocument/publishDiagnostics"
      uri = request[:params][:uri]
      synchronize_ui do
        diagnostics[uri] = request[:params][:diagnostics]
      end
    end
  end

  def synchronize_ui(&block)
    mutex.synchronize(&block)
  end

  def process_response(response)
    responses[response[:id]] = response
  end

  def send_request(id: nil, method:, params: nil, response_timeout: default_timeout)
    id ||= next_request_id
    Steep.logger.info "sending_request: id=#{id}, method=#{method}, params=#{params}"
    writer.write(id: id, method: method, params: params)

    if block_given?
      yield retrieve_response(id, timeout: response_timeout)
    else
      id
    end
  end

  def send_notification(method:, params: nil)
    Steep.logger.info "sending_notification: method=#{method}, params=#{params}"
    writer.write(method: method, params: params)
  end

  def retrieve_response(request_id, timeout: default_timeout)
    finally(timeout: timeout) do
      if responses.key?(request_id)
        return responses[request_id]
      end
    end

    nil
  end

  def finally(timeout: default_timeout)
    started_at = Time.now
    while Time.now < started_at + timeout
      yield
      sleep 0.2
    end
  end

  def open_file(path)
    send_notification(method: "textDocument/didOpen",
                      params: {
                        textDocument: {
                          uri: "#{file_scheme}#{path}"
                        }
                      })
  end

  def close_file(path)
    send_notification(method: "textDocument/didClose",
                      params: {
                        textDocument: {
                          uri: "#{file_scheme}#{path}"
                        }
                      })
  end

  def edit_file(path, content: nil, version:)
    send_notification(
      method: "textDocument/didChange",
      params: {
        textDocument: {
          uri: "#{file_scheme}#{path}",
          version: version
        },
        contentChanges: [
          {
            text: content
          }
        ]
      }
    )
  end

  def save_file(path)
    send_notification(
      method: "textDocument/didSave",
      params: {
        textDocument: { uri: "#{file_scheme}#{path}" }
      }
    )
  end

  def hover_on(path:, line:, character:)
    send_request(
      id: next_request_id,
      method: "textDocument/hover",
      params: {
        textDocument: { uri: "#{file_scheme}#{path}" },
        position: { line: line, character: character }
      }
    ) do |response|
      response[:result]
    end
  end

  def complete_on(path:, line:, character:, kind: LanguageServer::Protocol::Constant::CompletionTriggerKind::INVOKED, trigger_character: nil)
    send_request(
      id: next_request_id,
      method: "textDocument/completion",
      params: {
        textDocument: { uri: "#{file_scheme}#{path}" },
        position: { line: line, character: character },
        context: { triggerKind: kind, triggerCharacter: trigger_character }
      }
    ) do |response|
      response[:result]
    end
  end

  def workspace_symbol(query = "")
    send_request(
      id: next_request_id,
      method: "workspace/symbol",
      params: { query: query }
    ) do |response|
      response[:result]
    end
  end

  def diagnostics_for(path)
    diagnostics["#{file_scheme}#{path}"]
  end
end
