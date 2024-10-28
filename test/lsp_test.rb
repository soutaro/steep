require_relative "test_helper"

class LSPTest < Minitest::Test
  include TestHelper
  include ShellHelper

  class Client
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
              uri = URI.parse(message[:params][:uri])
              path = Pathname(uri.path)
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
    end

    protected

    def fresh_request_id
      @next_request_id += 1
    end
  end

  def dirs
    @dirs ||= []
  end

  def langserver_command(steepfile=nil)
    "#{RUBY_PATH} #{__dir__}/../exe/steep langserver --log-level=error".tap do |s|
      if steepfile
        s << " --steepfile=#{steepfile}"
      end
    end
  end

  def start_server()
    Open3.popen2(langserver_command(current_dir + "Steepfile")) do |stdin, stdout|
      reader = LanguageServer::Protocol::Transport::Io::Reader.new(stdout)

      writer = LanguageServer::Protocol::Transport::Io::Writer.new(stdin)

      client = Client.new(reader: reader, writer: writer, current_dir: current_dir)
      yield client
      client.join
    end
  end

  def write_file(path, content)
    (current_dir + path).parent.mkpath
    (current_dir + path).write(content)
  end

  def test_edit_files
    in_tmpdir do
      write_file("Steepfile", <<RUBY)
D = Steep::Diagnostic

target :core do
  check "lib/core"
  signature "sig/core"
end

target :main do
  check "lib/main"
  signature "sig/main"
end

target :test do
  unreferenced!

  check "test"
  signature "sig/test"
end
RUBY

      write_file("lib/core/core.rb", <<~RUBY)
        class Core
        end
      RUBY
      write_file("sig/core/core.rbs", <<~RBS)
        class Core
        end
      RBS
      write_file("lib/main/main.rb", <<~RUBY)
        class Main
        end
      RUBY
      write_file("sig/main/main.rbs", <<~RBS)
        class Main
        end
      RBS
      write_file("test/core_test.rb", <<~RUBY)
        class CoreTest
        end
      RUBY
      write_file("test/main_test.rb", <<~RUBY)
        class MainTest
        end
      RUBY
      write_file("sig/test/test.rbs", <<~RBS)
        class HelloTest
        end

        class MainTest
        end
      RBS

      start_server do |client|
        client.send_request(method: "initialize", params: { }) {}
        client.send_notification(method: "initialized", params: { })

        # client.open_file("lib/hello.rb")
        # client.edit_file("lib/hello.rb", <<~RUBY)
        # RUBY
        # client.save_file("lib/hello.rb")

        finally_holds(timeout: 3) do
          assert_operator client.diagnostics, :key?, Pathname("lib/core/core.rb")
          assert_operator client.diagnostics, :key?, Pathname("lib/main/main.rb")
          assert_operator client.diagnostics, :key?, Pathname("sig/core/core.rbs")
          assert_operator client.diagnostics, :key?, Pathname("sig/main/main.rbs")
          assert_operator client.diagnostics, :key?, Pathname("test/core_test.rb")
          assert_operator client.diagnostics, :key?, Pathname("test/main_test.rb")
          assert_operator client.diagnostics, :key?, Pathname("sig/test/test.rbs")
        end

        client.diagnostics.clear

        # Edit core.rbs and core.rb will be checked
        client.open_file("sig/core/core.rbs")
        client.change_file("sig/core/core.rbs") do
          <<~RBS
            class Core2
            end
          RBS
        end

        finally_holds(timeout: 3) do
          # Files in the same target is checked
          assert_operator client.diagnostics, :key?, Pathname("lib/core/core.rb")
          refute_operator client.diagnostics, :key?, Pathname("lib/main/main.rb")
          assert_operator client.diagnostics, :key?, Pathname("sig/core/core.rbs")
          refute_operator client.diagnostics, :key?, Pathname("sig/main/main.rbs")
          refute_operator client.diagnostics, :key?, Pathname("test/core_test.rb")
          refute_operator client.diagnostics, :key?, Pathname("test/main_test.rb")
          refute_operator client.diagnostics, :key?, Pathname("sig/test/test.rbs")
        end

        client.diagnostics.clear

        client.open_file("lib/core/core.rb")
        client.change_file("lib/core/core.rb") do
          <<~RBS
            class Core2
            end
          RBS
        end

        finally_holds(timeout: 3) do
          # The changed ruby script is checked
          assert_operator client.diagnostics, :key?, Pathname("lib/core/core.rb")
          refute_operator client.diagnostics, :key?, Pathname("lib/main/main.rb")
          refute_operator client.diagnostics, :key?, Pathname("sig/core/core.rbs")
          refute_operator client.diagnostics, :key?, Pathname("sig/main/main.rbs")
          refute_operator client.diagnostics, :key?, Pathname("test/core_test.rb")
          refute_operator client.diagnostics, :key?, Pathname("test/main_test.rb")
          refute_operator client.diagnostics, :key?, Pathname("sig/test/test.rbs")
        end

        client.diagnostics.clear

        client.open_file("lib/main/main.rb")

        client.change_file("sig/core/core.rbs") do
          <<~RBS
            class Core2
              def foo: () -> void
            end
          RBS
        end

        finally_holds(timeout: 3) do
          # The changed target and the open file are checked
          assert_operator client.diagnostics, :key?, Pathname("lib/core/core.rb")
          assert_operator client.diagnostics, :key?, Pathname("lib/main/main.rb")
          assert_operator client.diagnostics, :key?, Pathname("sig/core/core.rbs")
          refute_operator client.diagnostics, :key?, Pathname("sig/main/main.rbs")
          refute_operator client.diagnostics, :key?, Pathname("test/core_test.rb")
          refute_operator client.diagnostics, :key?, Pathname("test/main_test.rb")
          refute_operator client.diagnostics, :key?, Pathname("sig/test/test.rbs")
        end

        client.diagnostics.clear
      ensure
        client.send_request(method: "shutdown", params: nil) {}
        client.send_notification(method: "exit", params: nil)
      end
    end
  end

  def test_open_files
    in_tmpdir do
      write_file("Steepfile", <<RUBY)
D = Steep::Diagnostic

target :core do
  check "lib/core"
  signature "sig/core"
end

target :main do
  check "lib/main"
  signature "sig/main"
end

target :test do
  unreferenced!

  check "test"
  signature "sig/test"
end
RUBY

      write_file("lib/core/core.rb", <<~RUBY)
        class Core
        end
      RUBY
      write_file("sig/core/core.rbs", <<~RBS)
        class Core
        end
      RBS
      write_file("lib/main/main.rb", <<~RUBY)
        class Main
        end
      RUBY
      write_file("sig/main/main.rbs", <<~RBS)
        class Main
        end
      RBS
      write_file("test/core_test.rb", <<~RUBY)
        class CoreTest
        end
      RUBY
      write_file("test/main_test.rb", <<~RUBY)
        class MainTest
        end
      RUBY
      write_file("sig/test/test.rbs", <<~RBS)
        class HelloTest
        end

        class MainTest
        end
      RBS

      start_server do |client|
        client.send_request(method: "initialize", params: { }) {}
        client.send_notification(method: "initialized", params: { })

        finally_holds(timeout: 3) do
          assert_operator client.diagnostics, :key?, Pathname("lib/core/core.rb")
          assert_operator client.diagnostics, :key?, Pathname("lib/main/main.rb")
          assert_operator client.diagnostics, :key?, Pathname("sig/core/core.rbs")
          assert_operator client.diagnostics, :key?, Pathname("sig/main/main.rbs")
          assert_operator client.diagnostics, :key?, Pathname("test/core_test.rb")
          assert_operator client.diagnostics, :key?, Pathname("test/main_test.rb")
          assert_operator client.diagnostics, :key?, Pathname("sig/test/test.rbs")
        end

        client.diagnostics.clear

        # Opening files starts type checking them
        client.open_file("sig/core/core.rbs")
        client.open_file("test/main_test.rb")

        finally_holds(timeout: 3) do
          # Newly opened file is checked
          refute_operator client.diagnostics, :key?, Pathname("lib/core/core.rb")
          refute_operator client.diagnostics, :key?, Pathname("lib/main/main.rb")
          assert_operator client.diagnostics, :key?, Pathname("sig/core/core.rbs")
          refute_operator client.diagnostics, :key?, Pathname("sig/main/main.rbs")
          refute_operator client.diagnostics, :key?, Pathname("test/core_test.rb")
          assert_operator client.diagnostics, :key?, Pathname("test/main_test.rb")
          refute_operator client.diagnostics, :key?, Pathname("sig/test/test.rbs")
        end

        client.diagnostics.clear
      ensure
        client.send_request(method: "shutdown", params: nil) {}
        client.send_notification(method: "exit", params: nil)
      end
    end
  end
end
