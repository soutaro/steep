require "test_helper"

class WatchDriverTest < Minitest::Test
  include ShellHelper
  include TestHelper
  include Steep
  LSP = LanguageServer::Protocol

  Watch = Drivers::Watch

  def stdout
    @stdout ||= StringIO.new
  end

  def queue
    @queue ||= []
  end

  def pipe
    @pipe ||= IO.pipe
  end

  def client_writer
    @client_writer ||= LanguageServer::Protocol::Transport::Io::Writer.new(pipe[1])
  end

  def server_reader
    @server_reader ||= LanguageServer::Protocol::Transport::Io::Reader.new(pipe[0])
  end

  def read_one_message
    reads, * = IO.select([pipe[0]], [], [], 0.1)

    if reads
      buffer = reads[0].gets("\r\n\r\n")
      content_length = buffer.match(/Content-Length: (\d+)/i)[1].to_i
      message = reads[0].read(content_length) or raise
      JSON.parse(message, symbolize_names: true)
    end
  end

  def assert_message(method)
    message = read_one_message()
    refute_nil message
    assert_equal method, message[:method]

    if block_given?
      yield message[:params], message[:id]
    else
      message
    end
  end

  def project
    Project.new(steepfile_path: current_dir + "Steepfile")
  end

  def current_dir
    Pathname(@current_dir ||= Dir.mktmpdir)
  end

  def setup
    super


  end

  def teardown
    current_dir.rmtree
    super
  end

  def test_loop
    loop = Drivers::Watch::EventLoop.new(stdout: stdout, queue: queue, client_writer: client_writer, project: project, severity_level: :error)

    loop.handle_event(
      Watch::StartEvent.new(
        files: {
          Pathname("lib/foo.rb") => "1",
          Pathname("lib/bar.rb") => "[]"
        }
      )
    )

    assert_message("$/typecheck")

    loop.handle_event(
      Watch::ListenEvent.new(
        changes: {
          Pathname("lib/foo.rb") => "1+2"
        }
      )
    )

    assert_message("textDocument/didChange") do |params|
      assert_equal "file://#{current_dir}/lib/foo.rb", params[:textDocument][:uri]
      assert_equal "1+2", params[:contentChanges][0][:text]
    end

    guid = assert_message("$/typecheck") do |params|
      params[:guid]
    end

    loop.handle_event(
      Watch::LSPEvent.new(
        message: {
          method: "textDocument/publishDiagnostics",
          params: {
            uri: "file://#{current_dir}/lib/foo.rb",
            diagnostics: []
          }
        }
      )
    )

    loop.handle_event(
      Watch::LSPEvent.new(
        message: {
          method: "textDocument/publishDiagnostics",
          params: {
            uri: "file://#{current_dir}/lib/bar.rb",
            diagnostics: [
              {
                message: "Diagnostic message",
                code: "ERROR::CODE::123",
                severity: LSP::Constant::DiagnosticSeverity::ERROR,
                range: {
                  start: { line: 0, character: 0 },
                  end: { line: 0, character: 1 }
                }
              }
            ]
          }
        }
      )
    )

    loop.handle_event(
      Watch::LSPEvent.new(
        message: {
          method: "$/progress",
          params: {
            value: { kind: "end" },
            token: guid
          }
        }
      )
    )

    assert_equal <<MESSAGE, stdout.string
# Type checking files:



>> Cancelled 👋

# Type checking files:

.F

lib/bar.rb:1:0: [error] Diagnostic message
│ Diagnostic ID: ERROR::CODE::123
│
└ []
  ~

>> Type check completed in 0.01secs

MESSAGE
  end

  def test_loop_listen_event_nil
    loop = Drivers::Watch::EventLoop.new(stdout: stdout, queue: queue, client_writer: client_writer, project: project, severity_level: :error)

    loop.handle_event(
      Watch::StartEvent.new(
        files: {
          Pathname("lib/foo.rb") => "1+2",
          Pathname("lib/bar.rb") => "[].foo"
        }
      )
    )

    assert_message("$/typecheck")
  end

  def test_loop_start_type_checking
    loop = Drivers::Watch::EventLoop.new(stdout: stdout, queue: queue, client_writer: client_writer, project: project, severity_level: :error)

    loop.start_type_checking(
      changed_paths: Set["lib/foo.rb"],
      files: {
        Pathname("lib/foo.rb") => "1+2",
        Pathname("lib/bar.rb") => "[].foo"
      }
    )

    message = assert_message("$/typecheck")
    session = loop.current_session

    assert_equal message[:params][:guid], session.guid
    assert_equal Set["lib/foo.rb"], session.changed_paths

    assert_equal <<EOM, stdout.string
# Type checking files:

EOM
  end

  def test_loop_start_type_checking_merge
    loop = Drivers::Watch::EventLoop.new(stdout: stdout, queue: queue, client_writer: client_writer, project: project, severity_level: :error)

    loop.start_type_checking(
      changed_paths: Set["lib/foo.rb"],
      files: {
        Pathname("lib/foo.rb") => "1+2",
        Pathname("lib/bar.rb") => "[].foo"
      }
    )

    assert_message("$/typecheck")
    stdout.string = ""

    loop.start_type_checking(
      changed_paths: Set["lib/bar.rb"],
      files: {
        Pathname("lib/foo.rb") => "1+2",
        Pathname("lib/bar.rb") => "[].bar"
      }
    )

    message = assert_message("$/typecheck")
    session = loop.current_session

    assert_equal message[:params][:guid], session.guid
    assert_equal Set["lib/foo.rb", "lib/bar.rb"], session.changed_paths

    assert_equal <<EOM, stdout.string


>> Cancelled 👋

# Type checking files:

EOM
  end

  def test_loop_type_check_progress
    loop = Drivers::Watch::EventLoop.new(stdout: stdout, queue: queue, client_writer: client_writer, project: project, severity_level: :error)

    loop.start_type_checking(
      changed_paths: Set["lib/foo.rb"],
      files: {
        Pathname("lib/foo.rb") => "1+2",
        Pathname("lib/bar.rb") => "[].foo"
      }
    )
    assert_message("$/typecheck")

    stdout.string = ""

    loop.type_check_progress(Pathname("lib/foo.rb"), [])
    loop.type_check_progress(Pathname("lib/bar.rb"), [{ diagnostics: nil }])

    assert_equal ".F", stdout.string

    assert_equal(
      {
        Pathname("lib/foo.rb") => [],
        Pathname("lib/bar.rb") => [{ diagnostics: nil }]
      },
      loop.current_session.diagnostics
    )
  end

  def test_detail_result
    loop = Drivers::Watch::EventLoop.new(stdout: stdout, queue: queue, client_writer: client_writer, project: project, severity_level: :error)

    loop.start_type_checking(
      changed_paths: Set["lib/foo.rb"],
      files: {
        Pathname("lib/foo.rb") => "1+2",
        Pathname("lib/bar.rb") => "[].foo"
      }
    )

    loop.type_check_progress(Pathname("lib/foo.rb"), [])
    loop.type_check_progress(
      Pathname("lib/bar.rb"),
      [
        {
          message: "Diagnostic message",
          code: "ERROR::CODE::123",
          severity: LSP::Constant::DiagnosticSeverity::ERROR,
          range: {
            start: { line: 0, character: 0 },
            end: { line: 0, character: 1 }
          }
        }
      ]
    )

    stdout.string = ""

    loop.print_detail_result(loop.current_session)

    assert_equal <<MESSAGE, stdout.string
lib/bar.rb:1:0: [error] Diagnostic message
│ Diagnostic ID: ERROR::CODE::123
│
└ [].foo
  ~

MESSAGE
  end

  def test_print_compact_result
    loop = Drivers::Watch::EventLoop.new(stdout: stdout, queue: queue, client_writer: client_writer, project: project, severity_level: :error)

    new_diagnostic = ->(path) {
      {
        message: "Diagnostic message for #{path}",
        code: "ERROR::CODE::123",
        severity: LSP::Constant::DiagnosticSeverity::ERROR,
        range: {
          start: { line: 0, character: 0 },
          end: { line: 0, character: 1 }
        }
      }
    }

    diagnostics_changes = {
      # 0 => 0
      Pathname("lib/b.rb") => [
        [],
        []
      ],
      # 0 => 1
      Pathname("lib/c.rb") => [
        [],
        [new_diagnostic["lib/c.rb"]]
      ],
      # 1 => 0
      Pathname("lib/d.rb") => [
        [new_diagnostic["lib/d.rb"]],
        []
      ],
      # 1 => 1
      Pathname("lib/e.rb") => [
        [new_diagnostic["lib/e.rb"]],
        [new_diagnostic["lib/e.rb"]]
      ],
      # 1 => 2
      Pathname("lib/f.rb") => [
        [new_diagnostic["lib/f.rb"]],
        [new_diagnostic["lib/f.rb"], new_diagnostic["lib/f.rb(2)"]],
      ],
      # 2 => 1
      Pathname("lib/g.rb") => [
        [new_diagnostic["lib/g.rb"], new_diagnostic["lib/g.rb (2)"]],
        [new_diagnostic["lib/g.rb"]]
      ]
    }

    last_session = Drivers::Watch::Session.new(
      guid: "last_guid",
      changed_paths: Set[],
      files: {
        Pathname("lib/a.rb") => "1+2",
        Pathname("lib/b.rb") => "[].foo",
        Pathname("lib/c.rb") => "[].foo",
        Pathname("lib/d.rb") => "[].foo",
        Pathname("lib/e.rb") => "[].foo",
        Pathname("lib/f.rb") => "[].foo",
        Pathname("lib/g.rb") => "[].foo",
      },
      started_at: Time.now
    )
    last_session.diagnostics.merge!(
      {
        Pathname("lib/a.rb") => [],
        **diagnostics_changes.transform_values(&:first)
      }
    )

    current_session = Drivers::Watch::Session.new(
      guid: "current_session",
      changed_paths: Set[Pathname("lib/a.rb")],
      files: {
        Pathname("lib/a.rb") => "1+2",
        Pathname("lib/b.rb") => "[].foo",
        Pathname("lib/c.rb") => "[].foo",
        Pathname("lib/d.rb") => "[].foo",
        Pathname("lib/e.rb") => "[].foo",
        Pathname("lib/f.rb") => "[].foo",
        Pathname("lib/g.rb") => "[].foo",
      },
      started_at: Time.now
    )
    current_session.diagnostics.merge!(
      {
        Pathname("lib/a.rb") => [new_diagnostic["lib/a.rb"]],
        **diagnostics_changes.transform_values(&:last)
      }
    )

    stdout.string = ""

    loop.print_compact_result(current_session, last_session)

    assert_equal <<MESSAGE, stdout.string
lib/a.rb:1:0: [error] Diagnostic message for lib/a.rb
│ Diagnostic ID: ERROR::CODE::123
│
└ 1+2
  ~

  1 errors ( +1) on lib/c.rb
  0 errors ( -1) on lib/d.rb
  1 errors ( +0) on lib/e.rb
  2 errors ( +1) on lib/f.rb
  1 errors ( -1) on lib/g.rb

MESSAGE
  end
end
