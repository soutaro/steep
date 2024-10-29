require_relative "test_helper"
require_relative "lsp_client"

class LSPTest < Minitest::Test
  include TestHelper
  include ShellHelper

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

      client = LSPClient.new(reader: reader, writer: writer, current_dir: current_dir)
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

  def test_file_watcher
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

        client.open_file("sig/main/main.rbs")
        client.change_watched_file("sig/core/core.rbs")

        finally_holds(timeout: 3) do
          # All files are updated
          assert_operator client.diagnostics, :key?, Pathname("lib/core/core.rb")
          refute_operator client.diagnostics, :key?, Pathname("lib/main/main.rb")
          assert_operator client.diagnostics, :key?, Pathname("sig/core/core.rbs")
          assert_operator client.diagnostics, :key?, Pathname("sig/main/main.rbs")
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

  def test_workspace_symbol
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
        class Main__123
        end
      RUBY
      write_file("sig/main/main.rbs", <<~RBS)
        class Main__123
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

        client.workspace_symbol do |symbols|
          object = symbols.find { _1[:name] == "Object" }
          assert_operator object[:location][:uri], :end_with?, "core/object.rbs"
        end

        client.workspace_symbol("Main__123") do |symbols|
          assert_equal 1, symbols.size
        end

        client.open_file("sig/main/main.rbs")
        client.change_file("sig/main/main.rbs") {
          <<~RBS
            class Main_1234
            end
          RBS
        }

        finally_holds(timeout: 3) do
          client.workspace_symbol("Main") do |symbols|
            assert symbols.find { _1[:name] == "Main_1234"}
            refute symbols.find { _1[:name] == "Main_123"}
          end
        end
      ensure
        client.send_request(method: "shutdown", params: nil) {}
        client.send_notification(method: "exit", params: nil)
      end
    end
  end

  def test_goto_definition
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
        class CoreTest
          def core: () -> Core
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

        # Jump to RBS file works because the index updates immediately
        client.open_file("lib/core/core.rb")
        client.goto_definition("lib/core/core.rb", line: 0, character: 8) do |result|
          assert_any!(result) do |location|
            assert_operator location[:uri], :end_with?, "/sig/core/core.rbs"
            assert_equal({ line: 0, character: 6 }, location[:range][:start])
            assert_equal({ line: 0, character: 10 }, location[:range][:end])
          end
        end

        # Jump to RBS file works because the index updates immediately
        client.open_file("sig/test/test.rbs")
        client.goto_definition("sig/test/test.rbs", line: 1, character: 20) do |result|
          assert_any!(result) do |location|
            assert_operator location[:uri], :end_with?, "/sig/core/core.rbs"
            assert_equal({ line: 0, character: 6 }, location[:range][:start])
            assert_equal({ line: 0, character: 10 }, location[:range][:end])
          end
        end

        # Jump to Ruby file works when the Ruby code is already type checked
        client.open_file("sig/main/main.rbs")
        client.goto_definition("sig/main/main.rbs", line: 0, character: 8) do |result|
          assert_any!(result) do |location|
            assert_operator location[:uri], :end_with?, "/lib/main/main.rb"
            assert_equal({ line: 0, character: 6 }, location[:range][:start])
            assert_equal({ line: 0, character: 10 }, location[:range][:end])
          end
        end
      ensure
        client.send_request(method: "shutdown", params: nil) {}
        client.send_notification(method: "exit", params: nil)
      end
    end
  end

  def test_goto_implementation
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
        class CoreTest
          def core: () -> Core
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

        client.open_file("sig/test/test.rbs")
        client.goto_implementation("sig/test/test.rbs", line: 1, character: 20) do |result|
          assert_any!(result) do |location|
            assert_operator location[:uri], :end_with?, "/lib/core/core.rb"
            assert_equal({ line: 0, character: 6 }, location[:range][:start])
            assert_equal({ line: 0, character: 10 }, location[:range][:end])
          end
        end
      ensure
        client.send_request(method: "shutdown", params: nil) {}
        client.send_notification(method: "exit", params: nil)
      end
    end
  end
end
