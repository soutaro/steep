require "test_helper"

class InteractionWorkerTest < Minitest::Test
  include TestHelper
  include ShellHelper
  include LSPTestHelper

  include Steep

  InteractionWorker = Server::InteractionWorker
  ContentChange = Services::ContentChange

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

  def test_handle_request_initialize
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.parse(project, <<EOF)
target :lib do
  check "lib"
  signature "sig"
end
EOF

      worker = InteractionWorker.new(project: project, reader: worker_reader, writer: worker_writer)

      worker.handle_request({ method: "initialize", id: 1, params: nil })

      q = flush_queue(worker.queue)
      assert_equal 1, q.size
      assert_instance_of InteractionWorker::ApplyChangeJob, q[0]
    end
  end

  def test_handle_request_change
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.parse(project, <<EOF)
target :lib do
  check "lib"
  signature "sig"
end
EOF

      worker = InteractionWorker.new(project: project, reader: worker_reader, writer: worker_writer)

      worker.handle_request({ method: "initialize", id: 1, params: nil })
      flush_queue(worker.queue)

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

      q = flush_queue(worker.queue)
      assert_equal 1, q.size
      assert_instance_of InteractionWorker::ApplyChangeJob, q[0]

      refute_empty worker.buffered_changes
    end
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

      worker = InteractionWorker.new(project: project, reader: worker_reader, writer: worker_writer)

      worker.handle_request({ method: "initialize", id: 1, params: nil })
      flush_queue(worker.queue)

      worker.handle_request(
        {
          method: "textDocument/hover",
          params: {
            textDocument: { uri: "file://#{current_dir}/lib/hello.rb" },
            position: { line: 1, character: 2 }
          }
        }
      )

      q = flush_queue(worker.queue)
      assert_equal 1, q.size
      q[0].tap do |job|
        assert_instance_of InteractionWorker::HoverJob, job
        assert_equal Pathname("lib/hello.rb"), job.path
        assert_equal 2, job.line
        assert_equal 2, job.column
      end
    end
  end

  def test_handle_hover_job_success
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.parse(project, <<EOF)
target :lib do
  check "lib"
  signature "sig"
end
EOF

      worker = InteractionWorker.new(project: project, reader: worker_reader, writer: worker_writer)

      worker.service.update(
        changes: {
          Pathname("lib/foo.rb") => [ContentChange.string(<<RUBY)]
foo = 1 + 2
bar = foo.to_s
RUBY
        }
      ) {}

      response = worker.process_hover(InteractionWorker::HoverJob.new(path: Pathname("lib/foo.rb"), line: 1, column: 1))
      response = response.attributes

      assert_equal({ kind: "markdown", value: "`foo`: `::Integer`" }, response[:contents])
      assert_equal({ start: { line: 0, character: 0 }, end: { line: 0, character: 3 }}, response[:range])
    end
  end

  def test_handle_hover_invalid
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.parse(project, <<EOF)
target :lib do
  check "lib"
  signature "sig"
end
EOF

      worker = InteractionWorker.new(project: project, reader: worker_reader, writer: worker_writer)

      worker.service.update(
        changes: {
          Pathname("lib/foo.rb") => [ContentChange.string(<<RUBY)]
foo = 1 + 2
bar = foo.
RUBY
        }
      ) {}

      response = worker.process_hover(InteractionWorker::HoverJob.new(path: Pathname("lib/foo.rb"), line: 1, column: 1))
      assert_nil response
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

      worker.service.update(
        changes: {
          Pathname("lib/hello.rb") => [ContentChange.string(<<RUBY)]
foo = 100
foo + "bar"
RUBY
        }
      ) {}

      response = worker.process_completion(
        InteractionWorker::CompletionJob.new(
          path: Pathname("lib/hello.rb"),
          line: 3,
          column: 0,
          trigger: nil
        )
      )

      assert_instance_of LanguageServer::Protocol::Interface::CompletionList, response
    end
  end

  def test_completion_on_signature
    in_tmpdir do
      in_tmpdir do
        project = Project.new(steepfile_path: current_dir + "Steepfile")
        Project::DSL.parse(project, <<EOF)
target :lib do
  check "lib"
  signature "sig"
end
EOF
        worker = Server::InteractionWorker.new(project: project, reader: worker_reader, writer: worker_writer, queue: [])

        worker.service.update(
          changes: {
            Pathname("lib/hello.rbs") => [ContentChange.string(<<RUBY)]
class Foo
end
RUBY
          }
        ) {}

        response = worker.process_completion(
          InteractionWorker::CompletionJob.new(
            path: Pathname("sig/hello.rbs"),
            line: 3,
            column: 0,
            trigger: nil
          )
        )

        assert_nil response
      end
    end
  end
end
