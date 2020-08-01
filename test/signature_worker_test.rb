require "test_helper"

class SignatureWorkerTest < Minitest::Test
  include TestHelper
  include ShellHelper
  include LSPTestHelper

  include Steep

  LSP = LanguageServer::Protocol::Interface

  def dirs
    @dirs ||= []
  end

  def run_worker(worker)
    t = Thread.new do
      worker.run()
    end

    yield t

  ensure
    t.join

    reader_pipe[1].close
    writer_pipe[1].close
  end

  def shutdown!
    master_writer.write(
      method: :shutdown,
      params: nil
    )

    master_writer.write(
      method: :exit
    )
  end

  def test_worker_shutdown
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.parse(project, <<EOF)
target :lib do
  check "lib"
  signature "sig"
end
EOF

      run_worker(Server::SignatureWorker.new(project: project, reader: worker_reader, writer: worker_writer)) do |worker|
        master_writer.write(
          method: :shutdown,
          params: nil
        )

        master_writer.write(
          method: :exit
        )
      end
    end
  end

  def test_validation_enqueue
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.parse(project, <<EOF)
target :lib do
  check "lib"
  signature "sig"
end

target :test do
  check "test"
  signature "sig", "test/sig"
end
EOF

      worker = Server::SignatureWorker.new(project: project, reader: worker_reader, writer: worker_writer, queue: [])
      worker.queue_delay = 0

      lib_target = project.targets[0]
      test_target = project.targets[1]

      worker.handle_request(
        {
          method: "textDocument/didChange",
          params: LSP::DidChangeTextDocumentParams.new(
            text_document: {
              version: 1,
              uri: "file://#{current_dir}/sig/model.rbs"
            },
            content_changes: [
              {
                text: <<-RUBY
class Foo
end
                RUBY
              }
            ]
          ).to_hash
        }
      )

      assert_equal [lib_target, test_target], worker.queue.map(&:first)
      assert_instance_of Time, worker.last_target_validated_at[lib_target]
      assert_instance_of Time, worker.last_target_validated_at[test_target]

      worker.queue.clear

      worker.handle_request(
        {
          method: "textDocument/didChange",
          params: LSP::DidChangeTextDocumentParams.new(
            text_document: {
              version: 1,
              uri: "file://#{current_dir}/test/sig/test_helper.rbs"
            },
            content_changes: [
              {
                text: <<-RUBY
module TestHelper
end
                RUBY
              }
            ]
          ).to_hash
        }
      )

      assert_equal [test_target], worker.queue.map(&:first)
    end
  end

  def test_signature_validation_success
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.parse(project, <<EOF)
target :lib do
  check "lib"
  signature "sig"
end
EOF

      worker = Server::SignatureWorker.new(project: project, reader: worker_reader, writer: worker_writer, queue: [])
      lib_target = project.targets[0]

      lib_target.add_signature Pathname("sig/models.rbs"), <<-EOF
class Foo
end
      EOF

      thread = Thread.new do
        worker.validate_signature(lib_target, timestamp: Time.now)
      end

      master_reader.read do |req|
        assert_equal "textDocument/publishDiagnostics", req[:method]
        assert_operator req[:params][:uri], :end_with?, "sig/models.rbs"
        assert_empty req[:params][:diagnostics]
        break
      end

      thread.join
    end
  end

  def test_signature_validation_syntax_error
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.parse(project, <<EOF)
target :lib do
  check "lib"
  signature "sig"
end
EOF

      worker = Server::SignatureWorker.new(project: project, reader: worker_reader, writer: worker_writer, queue: [])
      lib_target = project.targets[0]

      lib_target.add_signature Pathname("sig/models.rbs"), <<-EOF
class Foo
      EOF

      thread = Thread.new do
        worker.validate_signature(lib_target, timestamp: Time.now)
      end

      master_reader.read do |req|
        assert_equal "textDocument/publishDiagnostics", req[:method]
        assert_operator req[:params][:uri], :end_with?, "sig/models.rbs"
        assert_equal 1, req[:params][:diagnostics].size

        req[:params][:diagnostics][0].tap do |diagnostic|
          assert_equal({
                         start: { line: 1, character: 0 },
                         end: { line: 1, character: 0 }
                       }, diagnostic[:range])
          assert_match(/parse error on value:/, diagnostic[:message])
        end

        break
      end

      thread.join
    end
  end

  def test_signature_validation_semantics_error
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.parse(project, <<EOF)
target :lib do
  check "lib"
  signature "sig"
end
EOF

      worker = Server::SignatureWorker.new(project: project, reader: worker_reader, writer: worker_writer, queue: [])
      lib_target = project.targets[0]

      lib_target.add_signature Pathname("sig/models.rbs"), <<-EOF
Name: Array[Integer, String]
      EOF

      thread = Thread.new do
        worker.validate_signature(lib_target, timestamp: Time.now)
      end
      thread.abort_on_exception = true

      master_reader.read do |req|
        assert_equal "textDocument/publishDiagnostics", req[:method]
        assert_operator req[:params][:uri], :end_with?, "sig/models.rbs"
        assert_equal 1, req[:params][:diagnostics].size

        req[:params][:diagnostics][0].tap do |diagnostic|
          assert_equal({
                         start: { line: 0, character: 6 },
                         end: { line: 0, character: 28 }
                       }, diagnostic[:range])
          assert_match(/InvalidTypeApplicationError:/, diagnostic[:message])
        end

        break
      end

      thread.join
    end
  end

  def test_run
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.parse(project, <<EOF)
target :lib do
  check "lib"
  signature "sig"
end
EOF

      requests = []
      t = Thread.new do
        master_reader.read do |request|
          requests << request
        end
      end

      run_worker(Server::SignatureWorker.new(project: project, reader: worker_reader, writer: worker_writer)) do |worker|
        master_writer.write(
          {
            method: "textDocument/didChange",
            params: LSP::DidChangeTextDocumentParams.new(
              text_document: LSP::VersionedTextDocumentIdentifier.new(
                version: 1,
                uri: "file://#{current_dir}/sig/hello.rbs"
              ),
              content_changes: [
                LSP::TextDocumentContentChangeEvent.new(
                  text: <<-RUBY
class Foo
end
                RUBY
                )
              ]
            )
          }
        )

        shutdown!
      end

      t.join

      assert requests.all? {|req|
        req[:method] == "textDocument/publishDiagnostics" &&
          req[:params][:uri].end_with?("sig/hello.rbs") &&
          req[:params][:diagnostics] == []
      }
    end
  end
end
