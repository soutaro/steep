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

    @default_timeout = 3
  end

  def next_request_id
    @next_request_id += 1
  end

  def start()
    raise if reader_thread

    @reader_thread = Thread.new do
      reader.read do |event|
        Steep.logger.info "received event: event=#{event}"

        if event.key?(:method)
          process_request event
        else
          process_response event
        end
      end
    end

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
    send_request(method: "exit")
    reader_thread.join
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
end
