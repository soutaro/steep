require_relative "test_helper"

class CommandSocketTest < Minitest::Test
  include TestHelper
  include ShellHelper

  def dirs
    @dirs ||= []
  end

  def langserver_command(steepfile)
    "#{RUBY_PATH} #{__dir__}/../exe/steep langserver --log-level=error --steepfile=#{steepfile}"
  end

  def socket_path
    project_id = Digest::MD5.hexdigest(current_dir.to_s)[0, 8]
    File.join(Dir.tmpdir, "steep-server", "steep-#{project_id}.sock")
  end

  def prepare_project
    (current_dir + "lib").mkdir
    (current_dir + "sig").mkdir
    (current_dir + "Steepfile").write(<<~RUBY)
      target :app do
        check "lib"
        signature "sig"
      end
    RUBY
    (current_dir + "lib/hello.rb").write(<<~RUBY)
      class Hello
        # @dynamic name
        attr_reader :name
      end
    RUBY
    (current_dir + "sig/hello.rbs").write(<<~RBS)
      class Hello
        attr_reader name: String
      end
    RBS
  end

  def start_langserver(command)
    Open3.popen2(command) do |stdin, stdout|
      reader = LanguageServer::Protocol::Transport::Io::Reader.new(stdout)
      writer = LanguageServer::Protocol::Transport::Io::Writer.new(stdin)

      responses = Thread::Queue.new
      reader_thread = Thread.new do
        begin
          reader.read do |message|
            if message[:id] && !message[:method]
              responses << message
            end
          end
        rescue IOError
          # Server exited
        end
      end

      writer.write(id: 1, method: "initialize", params: { capabilities: {} })
      Timeout.timeout(TestHelper.timeout) do
        response = responses.pop
        assert_equal 1, response[:id]
      end

      writer.write(method: "initialized", params: {})

      begin
        yield writer, responses
      ensure
        writer.write(id: 999, method: "shutdown", params: nil)
        Timeout.timeout(TestHelper.timeout) do
          loop do
            break if responses.pop[:id] == 999
          end
        end
        writer.write(method: "exit")
        reader_thread.join
      end
    end
  end

  def request_via_socket(message)
    UNIXSocket.open(socket_path) do |socket|
      socket_reader = LanguageServer::Protocol::Transport::Io::Reader.new(socket)
      socket_writer = LanguageServer::Protocol::Transport::Io::Writer.new(socket)

      socket_writer.write(message)

      Timeout.timeout(TestHelper.timeout) do
        socket_reader.read do |response|
          return response
        end
      end
    end
  end

  def test_langserver_serves_requests_through_command_socket
    skip "UNIX socket is not supported on this platform" if Gem.win_platform?

    in_tmpdir do
      prepare_project

      start_langserver(langserver_command(current_dir + "Steepfile")) do |writer, responses|
        Timeout.timeout(TestHelper.timeout) do
          sleep 0.1 until File.socket?(socket_path)
        end

        # A request is routed to the master and the response comes back with the original id
        response = request_via_socket(id: "ping-1", method: "$/ping", params: { message: "hello" })
        assert_equal "ping-1", response[:id]
        assert_equal({ message: "hello" }, response[:result])

        # LSP requests work through the socket
        response = request_via_socket(
          id: 55,
          method: "textDocument/hover",
          params: {
            textDocument: { uri: "file://#{current_dir}/lib/hello.rb" },
            position: { line: 2, character: 15 }
          }
        )
        assert_equal 55, response[:id]

        # Lifecycle methods are rejected
        response = request_via_socket(id: "bad-1", method: "shutdown", params: nil)
        assert_equal "bad-1", response[:id]
        refute_nil response[:error]
      end

      refute File.exist?(socket_path), "The socket file should be cleaned up on exit"
    end
  end

  def test_langserver_with_no_command_socket_option
    skip "UNIX socket is not supported on this platform" if Gem.win_platform?

    in_tmpdir do
      prepare_project

      start_langserver("#{langserver_command(current_dir + "Steepfile")} --no-command-socket") do |writer, responses|
        response = nil
        assert_raises(Timeout::Error) do
          Timeout.timeout(3) do
            sleep 0.1 until File.socket?(socket_path)
          end
        end
      end
    end
  end
end
