require_relative "test_helper"

class LangserverTest < Minitest::Test
  include TestHelper
  include ShellHelper

  def dirs
    @dirs ||= []
  end

  def langserver_command(steepfile=nil)
    "#{__dir__}/../exe/steep langserver --log-level=error".tap do |s|
      if steepfile
        s << " --steepfile=#{steepfile}"
      end
    end
  end

  def test_initialize
    in_tmpdir do
      (current_dir + "Steepfile").write <<EOF
target :app do end
EOF

      Open3.popen2(langserver_command(current_dir + "Steepfile")) do |stdin, stdout|
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

      Open3.popen2(langserver_command(path + "Steepfile")) do |stdin, stdout|
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
                version: 3,
              },
              contentChanges: [{text: "1.to_s" }]
            }
          )

          finally_holds do
            lsp.synchronize_ui do
              assert_equal [], lsp.diagnostics["file://#{path}/workdir/example.rb"]
            end
          end

          lsp.send_request(
            method: "textDocument/didChange",
            params: {
              textDocument: {
                uri: "file://#{path}/workdir/example.rb",
                version: 4,
              },
              contentChanges: [{text: <<SRC }]
def foo
  # @type var string:
end
SRC
            }
          )

          assert_finally do
            lsp.synchronize_ui do
              lsp.diagnostics["file://#{path}/workdir/example.rb"].any? {|error|
                error[:message].start_with?("Syntax error on annotation: `@type var string:`,")
              }
            end
          end
        end
      end
    end
  end

  def test_hover
    in_tmpdir do
      path = current_dir.realpath

      (path + "Steepfile").write <<EOF
target :app do
  check "lib"
  signature "sig"
end
EOF

      (path+"sig").mkdir
      (path+"sig/example.rbs").write <<RBS
class Hello
  def foo: (Integer x) -> String
end
RBS
      (path+"lib").mkdir
      (path+"lib/example.rb").write <<RB
class Hello
  def foo(x)
    (x + 1).to_s
  end
end
RB

      Open3.popen2(langserver_command(path + "Steepfile")) do |stdin, stdout|
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
              assert_equal [], lsp.diagnostics["file://#{path}/lib/example.rb"]
              assert_equal [], lsp.diagnostics["file://#{path}/sig/example.rbs"]
            end
          end

          lsp.send_request(
            method: "textDocument/hover",
            params: {
              textDocument: {
                uri: "file://#{path}/lib/example.rb"
              },
              position: {
                line: 2,
                character: 5
              }
            }
          ) do |response|
            assert_equal "`x`: `::Integer`", response[:result][:contents][:value]
            assert_equal({ start: { line: 2, character: 5 }, end: { line: 2, character: 6 }}, response[:result][:range])
          end

          lsp.send_request(
            method: "textDocument/hover",
            params: {
              textDocument: {
                uri: "file://#{path}/lib/example.rb"
              },
              position: {
                line: 2,
                character: 9
              }
            }
          ) do |response|
            assert_equal "`::Integer`", response[:result][:contents][:value]
            assert_equal({ start: { line: 2, character: 9 }, end: { line: 2, character: 10 }}, response[:result][:range])
          end

          lsp.send_request(
            method: "textDocument/hover",
            params: {
              textDocument: {
                uri: "file://#{path}/lib/example.rb"
              },
              position: {
                line: 2,
                character: 12
              }
            }
          ) do |response|
            assert_equal <<MSG, response[:result][:contents][:value]
```
::Integer#to_s ~> ::String
```

----

Returns a string containing the place-value representation of `int` with radix
`base` (between 2 and 36).

    12345.to_s       #=> \"12345\"
    12345.to_s(2)    #=> \"11000000111001\"
    12345.to_s(8)    #=> \"30071\"
    12345.to_s(10)   #=> \"12345\"
    12345.to_s(16)   #=> \"3039\"
    12345.to_s(36)   #=> \"9ix\"
    78546939656932.to_s(36)  #=> \"rubyrules\"


----

- `() -> ::String`
- `(2) -> ::String`
- `(3) -> ::String`
- `(4) -> ::String`
- `(5) -> ::String`
- `(6) -> ::String`
- `(7) -> ::String`
- `(8) -> ::String`
- `(9) -> ::String`
- `(10) -> ::String`
- `(11) -> ::String`
- `(12) -> ::String`
- `(13) -> ::String`
- `(14) -> ::String`
- `(15) -> ::String`
- `(16) -> ::String`
- `(17) -> ::String`
- `(18) -> ::String`
- `(19) -> ::String`
- `(20) -> ::String`
- `(21) -> ::String`
- `(22) -> ::String`
- `(23) -> ::String`
- `(24) -> ::String`
- `(25) -> ::String`
- `(26) -> ::String`
- `(27) -> ::String`
- `(28) -> ::String`
- `(29) -> ::String`
- `(30) -> ::String`
- `(31) -> ::String`
- `(32) -> ::String`
- `(33) -> ::String`
- `(34) -> ::String`
- `(35) -> ::String`
- `(36) -> ::String`
- `(::int base) -> ::String`
MSG
            assert_equal({ start: { line: 2, character: 4 }, end: { line: 2, character: 16 }}, response[:result][:range])
          end
        end
      end
    end
  end
end
