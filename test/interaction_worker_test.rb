require_relative "test_helper"

class InteractionWorkerTest < Minitest::Test
  include TestHelper
  include ShellHelper
  include LSPTestHelper

  include Steep

  LSP = LanguageServer::Protocol
  InteractionWorker = Server::InteractionWorker
  ContentChange = Services::ContentChange

  include Server::CustomMethods

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
      worker.handle_request({ method: FileLoad::METHOD, params: { content: {} } })
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
              uri: "#{file_scheme}#{current_dir}/lib/hello.rb"
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

      refute_empty worker.buffered_changes
    end
  end

  def test_handle_request__file_reset
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
          method: FileReset::METHOD,
          id: 123,
          params: {
            uri: "#{file_scheme}#{current_dir}/lib/hello.rb",
            content: "1 + true"
          }
        }
      )

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
            textDocument: { uri: "#{file_scheme}#{current_dir}/lib/hello.rb" },
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

      assert_instance_of LSP::Interface::Hover, response
      assert_equal({ start: { line: 0, character: 0 }, end: { line: 0, character: 3 }}.to_json, response.range.to_json)
    end
  end

  def test_handle_alias_hover_job_success_on_rbs
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
          Pathname("sig/hello.rbs") => [ContentChange.string(<<RBS)]
# here is your comments
type foo = Integer | String

class FooBar
  def f: (foo) -> void
end
RBS
        }
      ) {}

      response = worker.process_hover(InteractionWorker::HoverJob.new(path: Pathname("sig/hello.rbs"), line: 5, column: 11))

      assert_instance_of LSP::Interface::Hover, response
      assert_equal({ start: { line: 4, character: 10 }, end: { line: 4, character: 13 } }.to_json, response.range.to_json)
    end
  end

  def test_handle_interface_hover_job_success_on_rbs
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
          Pathname("sig/hello.rbs") => [ContentChange.string(<<RBS)]
# here is your comments
interface _Fooable
  def foo: () -> nil
end

class Test
  def foo: (_Fooable) -> nil
end
RBS
        }
      ) {}

      response = worker.process_hover(InteractionWorker::HoverJob.new(path: Pathname("sig/hello.rbs"), line: 7, column: 13))

      assert_instance_of LSP::Interface::Hover, response
      assert_equal({ start: { line: 6, character: 12 }, end: { line: 6, character: 20 } }.to_json, response.range.to_json)
    end
  end

  def test_handle_class_hover_job_success_on_rbs
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
          Pathname("sig/hello.rbs") => [ContentChange.string(<<RBS)]
# here is your comments
class Foo [T] < Parent[T] end
class Parent [in T] end
module Hoge end
class Qux
  @foo: Foo[Hoge]
end
RBS
        }
      ) {}

      response = worker.process_hover(InteractionWorker::HoverJob.new(path: Pathname("sig/hello.rbs"), line: 6, column: 10))

      assert_instance_of LSP::Interface::Hover, response
      assert_equal({ start: { line: 5, character: 8 }, end: { line: 5, character: 11 } }.to_json, response.range.to_json)
    end
  end

  def test_handle_class_hover_strip_html_comment
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
          Pathname("sig/hello.rbs") => [ContentChange.string(<<RBS)]
# <!-- HTML comment here -->
# This is comment content
class Foo[T] end

type hello = Foo[String]
RBS
        }
      ) {}

      response = worker.process_hover(InteractionWorker::HoverJob.new(path: Pathname("sig/hello.rbs"), line: 5, column: 15))

      assert_instance_of LSP::Interface::Hover, response
      assert_equal({start:{line:4,character:13},end:{line:4,character:16}}.to_json, response.range.to_json)
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
          changes:{
            Pathname("sig/hello.rbs") => [ContentChange.string(<<~RBS)]
              class Hoge end
              class Qux
                @foo: H
              end
            RBS
          }
        ) {}

        response = worker.process_completion(
          InteractionWorker::CompletionJob.new(
            path: Pathname("sig/hello.rbs"),
            line: 3,
            column: 9,
            trigger: nil
          )
        )

        assert_instance_of LanguageServer::Protocol::Interface::CompletionList, response

        assert_any!(response.items) do |item|
          assert_equal "Hash", item.label
          assert_instance_of LanguageServer::Protocol::Interface::MarkupContent, item.documentation
        end

        assert_any!(response.items) do |item|
          assert_equal "Hoge", item.label
        end
      end
    end
  end
end

