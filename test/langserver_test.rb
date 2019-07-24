require_relative "test_helper"

class LangserverTest < Minitest::Test
  include ShellHelper

  def dirs
    @dirs ||= []
  end

  def langserver_command
    "#{__dir__}/../exe/steep langserver #{current_dir}"
  end

  def jsonrpc(hash)
    hash_str = hash.to_json
    "Content-Length: #{hash_str.bytesize}\r\n" + "\r\n" + hash_str
  end

  def test_initialize
    in_tmpdir do
      Open3.popen3(langserver_command) do |stdin, stdout, stderr, wait_thr|
        stdin.puts jsonrpc(
          id: 0,
          method: "initialize",
          params: {},
          jsonrpc: "2.0",
        )
        stdin.close
        wait_thr.join

        assert_equal jsonrpc(
          id: 0,
          result: {
            capabilities: {
              textDocumentSync: { openClose: true, change: 1 },
              hoverProvider:true
            }
          },
          jsonrpc: "2.0",
        ), stdout.read
      end
    end
  end

  def test_did_open
    in_tmpdir do
      Open3.popen3(langserver_command, chdir: current_dir.to_s) do |stdin, stdout, stderr, wait_thr|
        stdin.puts jsonrpc(
          method: "textDocument/didOpen",
          params: {
            textDocument: {
              uri: "file:///root/workdir/example.rb",
              languageId: "ruby",
              version: 1,
              text: "[\"foo\"].join(\",\").map {|str| puts str}",
            }
          }
        )
        stdin.close
        wait_thr.join

        assert_equal jsonrpc(
          method: "textDocument/publishDiagnostics",
          params: {
            uri: "file:///root/workdir/example.rb",
            diagnostics: [{
              range: {
                start: { line: 0, character: 0 },
                end: { line: 0, character: 38 },
              },
              severity: 1,
              message: "/root/workdir/example.rb:1:0: NoMethodError: type=::String, method=map"
            }]
          },
          jsonrpc: "2.0",
        ), stdout.read
      end
    end
  end

  def test_did_change
    in_tmpdir do
      Open3.popen3(langserver_command, chdir: current_dir.to_s) do |stdin, stdout, stderr, wait_thr|
        stdin.puts jsonrpc(
                     method: "textDocument/didOpen",
                     params: {
                       textDocument: {
                         uri: "file:///root/workdir/example.rb",
                         languageId: "ruby",
                         version: 1,
                         text: "",
                       }
                     }
                   )
        stdin.puts jsonrpc(
          method: "textDocument/didChange",
          params: {
            textDocument: {
              uri: "file:///root/workdir/example.rb",
              version: 2,
            },
            contentChanges: [
              { text: "[\"foo\"].join(\",\").map {|str| puts str}" }
            ]
          }
        )
        stdin.close
        wait_thr.join

        assert_equal [
                       jsonrpc(
                         method: "textDocument/publishDiagnostics",
                         params: {
                           uri: "file:///root/workdir/example.rb",
                           diagnostics: []
                         },
                         jsonrpc: "2.0",),
                       jsonrpc(
                         method: "textDocument/publishDiagnostics",
                         params: {
                           uri: "file:///root/workdir/example.rb",
                           diagnostics: [{
                                           range: {
                                             start: { line: 0, character: 0 },
                                             end: { line: 0, character: 38 },
                                           },
                                           severity: 1,
                                           message: "/root/workdir/example.rb:1:0: NoMethodError: type=::String, method=map"
                                         }]
                         },
                         jsonrpc: "2.0",
                         )
                     ].join(""), stdout.read
      end
    end
  end
end
