require_relative "test_helper"

class LangserverTest < Minitest::Test
  include TestHelper
  include ShellHelper

  def dirs
    @dirs ||= []
  end

  def langserver_command
    "#{__dir__}/../exe/steep langserver --log-level=error"
  end

  def test_initialize
    in_tmpdir do
      (current_dir + "Steepfile").write <<EOF
target :app do end
EOF

      Open3.popen2(langserver_command, chdir: current_dir) do |stdin, stdout|
        reader = LanguageServer::Protocol::Transport::Io::Reader.new(stdout)
        writer = LanguageServer::Protocol::Transport::Io::Writer.new(stdin)

        lsp = LSPDouble.new(reader: reader, writer: writer)

        lsp.start do
          lsp.send_request(method: "initialize") do |response|
            assert_equal(
              {
                id: response[:id],
                result: {
                  capabilities: {
                    textDocumentSync: { change: 1 },
                    hoverProvider: true,
                  }
                },
                jsonrpc: "2.0"
              },
              response
            )
          end
        end
      end
    end
  end

  def test_did_change
    in_tmpdir do
      path = current_dir.realpath

      (path + "Steepfile").write <<EOF
target :app do
  check "workdir/example.rb"
end
EOF
      (path+"workdir").mkdir
      (path+"workdir/example.rb").write ""

      Open3.popen2(langserver_command, chdir: path.to_s) do |stdin, stdout|
        reader = LanguageServer::Protocol::Transport::Io::Reader.new(stdout)
        writer = LanguageServer::Protocol::Transport::Io::Writer.new(stdin)

        lsp = LSPDouble.new(reader: reader, writer: writer)

        lsp.start do
          lsp.send_request(method: "initialize") do |response|
            assert_equal(
              {
                id: response[:id],
                result: {
                  capabilities: {
                    textDocumentSync: { change: 1 },
                    hoverProvider: true,
                  }
                },
                jsonrpc: "2.0"
              },
              response
            )
          end

          finally_holds timeout: 30 do
            lsp.synchronize_ui do
              assert_equal [], lsp.diagnostics["file://#{path}/workdir/example.rb"]
            end
          end

          lsp.send_request(
            method: "textDocument/didChange",
            params: {
              textDocument: {
                uri: "file://#{path}/workdir/example.rb",
                version: 2,
              },
              contentChanges: [{text: "1.map()" }]
            }
          )

          assert_finally do
            lsp.synchronize_ui do
              lsp.diagnostics["file://#{path}/workdir/example.rb"].any? {|error|
                error[:message] == "workdir/example.rb:1:0: NoMethodError: type=::Integer, method=map"
              }
            end
          end

          lsp.send_request(
            method: "textDocument/didChange",
            params: {
              textDocument: {
                uri: "file://#{path}/workdir/example.rb",
                version: 2,
              },
              contentChanges: [{text: "1.to_s" }]
            }
          )

          finally_holds do
            lsp.synchronize_ui do
              assert_equal [], lsp.diagnostics["file://#{path}/workdir/example.rb"]
            end
          end
        end
      end
    end
  end
end
