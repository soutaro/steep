require_relative "test_helper"

class LangserverTest < Minitest::Test
  include ShellHelper

  def dirs
    @dirs ||= []
  end

  def langserver_command
    "#{__dir__}/../exe/steep langserver --log-level=info"
  end

  def jsonrpc(hash)
    hash_str = hash.to_json
    "Content-Length: #{hash_str.bytesize}\r\n" + "\r\n" + hash_str
  end

  def test_initialize
    in_tmpdir do
      (current_dir + "Steepfile").write <<EOF
target :app do end
EOF

      Open3.popen3(langserver_command, chdir: current_dir) do |stdin, stdout, stderr, wait_thr|
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
              textDocumentSync: { change: 1 },
              hoverProvider: true
            }
          },
          jsonrpc: "2.0",
        ), stdout.read
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

      Open3.popen3(langserver_command, chdir: path.to_s) do |stdin, stdout, stderr, wait_thr|
        stdin.puts jsonrpc(
                     id: 0,
                     method: "initialize",
                     params: {},
                     jsonrpc: "2.0",
                     )
        stdin.puts jsonrpc(
                     id: 1,
                     method: "textDocument/didChange",
                     params: {
                       textDocument: {
                         uri: "file://#{path}/workdir/example.rb",
                         version: 2,
                       },
                       contentChanges: [
                         { text: <<-EOF }
1.map()
                         EOF
                       ]
                     }
                   )
        stdin.close
        wait_thr.join

        assert_equal [
                       jsonrpc(
                         id: 0,
                         result: {
                           "capabilities": {
                             "textDocumentSync": { change: 1 },
                             hoverProvider: true
                           }
                         },
                         jsonrpc: "2.0",
                         ),
                       jsonrpc(
                         method: "textDocument/publishDiagnostics",
                         params: {
                           uri: "file://#{path}/workdir/example.rb",
                           diagnostics: []
                         },
                         jsonrpc: "2.0",
                         ),
                       jsonrpc(
                         method: "textDocument/publishDiagnostics",
                         params: {
                           uri: "file://#{path}/workdir/example.rb",
                           diagnostics: [
                             {
                               range: {
                                 start: { line: 0, character: 0 },
                                 end: { line: 0, character: 7 },
                               },
                               severity: 1,
                               message: "workdir/example.rb:1:0: NoMethodError: type=::Integer, method=map"
                             }
                           ]
                         },
                         jsonrpc: "2.0",
                         )
                     ].join(""), stdout.read
      end
    end
  end
end
