require "test_helper"

class InteractionWorkerTest < Minitest::Test
  include TestHelper
  include ShellHelper
  include LSPTestHelper

  include Steep

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

  def dirs
    @dirs ||= []
  end

  def test_handle_request_hover
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.parse(project, <<EOF)
target :lib do
  check "lib"
  signature "sig"
end
EOF
      target = project.targets[0]

      worker = Server::InteractionWorker.new(project: project, reader: worker_reader, writer: worker_writer, queue: [])

      worker.handle_request(
        {
          method: "textDocument/didChange",
          id: 123,
          params: LSP::Interface::DidChangeTextDocumentParams.new(
            text_document: {
              version: 1,
              uri: "file://#{current_dir}/lib/hello.rb"
            },
            content_changes: [
              {
                text: <<-RUBY
foo = 100
foo.to_s(8)

class String
  def to_s
  end
end
                RUBY
              }
            ]
          ).to_hash
        }
      )

      refute_empty target.source_files[Pathname("lib/hello.rb")].content

      worker.handle_request(
        {
          method: "textDocument/hover",
          params: {
            textDocument: { uri: "file://#{current_dir}/lib/hello.rb" },
            position: { line: 1, character: 2 }
          }
        }
      )

      assert_equal 1, worker.queue.size

      response = worker.queue.pop
      assert_equal "`foo`: `::Integer`", response[:result].contents[:value]

      worker.handle_request(
        {
          method: "textDocument/hover",
          params: {
            textDocument: { uri: "file://#{current_dir}/lib/hello.rb" },
            position: { line: 1, character: 6 }
          }
        }
      )

      assert_equal 1, worker.queue.size

      response = worker.queue.pop
      assert_match(/Returns a string containing the place-value representation of `int` with radix/, response[:result].contents[:value])

      worker.handle_request(
        {
          method: "textDocument/hover",
          params: {
            textDocument: { uri: "file://#{current_dir}/lib/hello.rb" },
            position: { line: 4, character: 6 }
          }
        }
      )

      assert_equal 1, worker.queue.size

      response = worker.queue.pop
      assert_match(/Returns `self`/, response[:result].contents[:value])
    end
  end

  def test_hover_on_syntax_error
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.parse(project, <<EOF)
target :lib do
  check "lib"
  signature "sig"
end
EOF
      worker = Server::InteractionWorker.new(project: project, reader: worker_reader, writer: worker_writer, queue: [])

      worker.handle_request(
        {
          id: 123,
          method: "textDocument/didChange",
          params: LSP::Interface::DidChangeTextDocumentParams.new(
            text_document: {
              version: 1,
              uri: "file://#{current_dir}/lib/hello.rb"
            },
            content_changes: [
              {
                text: <<-RUBY
foo = 100
foo + "ba
                RUBY
              }
            ]
          ).to_hash
        }
      )

      worker.handle_request(
        {
          method: "textDocument/hover",
          params: {
            textDocument: { uri: "file://#{current_dir}/lib/hello.rb" },
            position: { line: 1, character: 2 }
          }
        }
      )

      assert_equal 1, worker.queue.size
      assert_nil worker.queue[0][:result]
    end
  end

  def test_hover_on_signature
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.parse(project, <<EOF)
target :lib do
  check "lib"
  signature "sig"
end
EOF
      worker = Server::InteractionWorker.new(project: project, reader: worker_reader, writer: worker_writer, queue: [])

      worker.handle_request(
        {
          id: 123,
          method: "textDocument/didChange",
          params: LSP::Interface::DidChangeTextDocumentParams.new(
            text_document: {
              version: 1,
              uri: "file://#{current_dir}/sig/hello.rbs"
            },
            content_changes: [
              {
                text: <<-RUBY
class Integer
end
                RUBY
              }
            ]
          ).to_hash
        }
      )

      worker.handle_request(
        {
          method: "textDocument/hover",
          params: {
            textDocument: { uri: "file://#{current_dir}/sig/hello.rbs" },
            position: { line: 1, character: 2 }
          }
        }
      )

      assert_equal 1, worker.queue.size
      assert_nil worker.queue[0][:result]
    end
  end

  def test_handle_completion_request
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.parse(project, <<EOF)
target :lib do
  check "lib"
  signature "sig"
end
EOF
      worker = Server::InteractionWorker.new(project: project, reader: worker_reader, writer: worker_writer, queue: [])

      worker.handle_request(
        {
          id: 123,
          method: "textDocument/didChange",
          params: LSP::Interface::DidChangeTextDocumentParams.new(
            text_document: {
              version: 1,
              uri: "file://#{current_dir}/lib/hello.rb"
            },
            content_changes: [
              {
                text: <<-RUBY
foo = 100
foo + "bar"
                RUBY
              }
            ]
          ).to_hash
        }
      )

      worker.handle_request(
        {
          id: 234,
          method: "textDocument/completion",
          params: {
            textDocument: { uri: "file://#{current_dir}/lib/hello.rb" },
            position: {
              line: 2,
              character: 0
            },
            context: {
              triggerKind: LSP::Constant::CompletionTriggerKind::INVOKED
            }
          }
        }
      )

      response = worker.queue.first

      assert_equal 234, response[:id]
    end
  end

  def test_completion_on_signature
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.parse(project, <<EOF)
target :lib do
  check "lib"
  signature "sig"
end
EOF
      worker = Server::InteractionWorker.new(project: project, reader: worker_reader, writer: worker_writer, queue: [])

      worker.handle_request(
        {
          id: 123,
          method: "textDocument/didChange",
          params: LSP::Interface::DidChangeTextDocumentParams.new(
            text_document: {
              version: 1,
              uri: "file://#{current_dir}/sig/hello.rbs"
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

      worker.handle_request(
        {
          id: 234,
          method: "textDocument/completion",
          params: {
            textDocument: { uri: "file://#{current_dir}/sig/hello.rbs" },
            position: {
              line: 1,
              character: 3
            },
            context: {
              triggerKind: LSP::Constant::CompletionTriggerKind::INVOKED
            }
          }
        }
      )

      response = worker.queue.first

      assert_equal 234, response[:id]
      assert_nil response[:result]
    end
  end
end
