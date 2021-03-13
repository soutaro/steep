require "test_helper"

class TypeCheckWorkerTest < Minitest::Test
  include TestHelper
  include ShellHelper
  include LSPTestHelper

  include Steep

  LSP = LanguageServer::Protocol::Interface

  ContentChange = Services::ContentChange

  def flush_queue(queue)
    queue << self

    copy = []

    while true
      ret = queue.pop

      break if ret.nil?
      break if ret.equal?(self)

      copy << ret
    end

    copy
  end

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
      id: -123,
      method: :shutdown,
      params: nil
    )

    master_reader do |response|
      break if response[:id] == -123
    end

    master_writer.write(
      method: :exit
    )
  end

  def assignment
    @assignment ||= Services::PathAssignment.all
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

      run_worker(
        Server::TypeCheckWorker.new(
          project: project,
          assignment: assignment,
          commandline_args: [],
          reader: worker_reader,
          writer: worker_writer)
      ) do |worker|
        master_writer.write(
          id: 123,
          method: :shutdown,
          params: nil
        )

        master_reader.read do |response|
          break if response[:id] == 123
        end

        master_writer.write(
          method: :exit
        )
      end
    end
  end

  def test_handle_initialize
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.parse(project, <<EOF)
target :lib do
  check "lib"
  signature "sig"
end
EOF

      worker = Server::TypeCheckWorker.new(
        project: project,
        assignment: assignment,
        commandline_args: [],
        reader: worker_reader,
        writer: worker_writer
      )

      worker.handle_request(
        {
          id: 0,
          method: "initialize",
          params: nil
        }
      )

      jobs = flush_queue(worker.queue)

      assert_equal 1, jobs.size
      assert_instance_of Server::TypeCheckWorker::TypeCheckJob, jobs[0]
    end
  end

  def test_handle_update
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.parse(project, <<EOF)
target :lib do
  check "lib"
  signature "sig"
end
EOF

      worker = Server::TypeCheckWorker.new(
        project: project,
        assignment: assignment,
        commandline_args: [],
        reader: worker_reader,
        writer: worker_writer
      )

      worker.handle_request(
        {
          method: "textDocument/didChange",
          params: LSP::DidChangeTextDocumentParams.new(
            text_document: LSP::VersionedTextDocumentIdentifier.new(
              version: 1,
              uri: "file://#{current_dir}/lib/hello.rb"
            ).to_hash,
            content_changes: [
              LSP::TextDocumentContentChangeEvent.new(
                text: <<-RUBY
class Foo
end
              RUBY
              ).to_hash
            ]
          ).to_hash
        }
      )

      jobs = flush_queue(worker.queue)

      assert_equal 1, jobs.size
      assert_instance_of Server::TypeCheckWorker::TypeCheckJob, jobs[0]

      changes = worker.pop_buffer
      assert_equal({ Pathname("lib/hello.rb") => [Services::ContentChange.string("class Foo\nend\n")] }, changes)
    end
  end

  def test_job_typecheck
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.parse(project, <<EOF)
target :lib do
  check "lib"
  signature "sig"
end
EOF

      reader = Thread.new do
        responses = []

        master_reader.read do |response|
          break if response[:method] == "close"
          responses << response
        end

        responses
      end

      worker = Server::TypeCheckWorker.new(
        project: project,
        assignment: assignment,
        commandline_args: [],
        reader: worker_reader,
        writer: worker_writer
      )

      worker.push_buffer do |changes|
        changes[Pathname("lib/hello.rb")] = [Services::ContentChange.string(<<EOF)]
Hello.new.world(10)
EOF
        changes[Pathname("sig/hello.rbs")] = [Services::ContentChange.string(<<EOF)]
class Hello
  def world: () -> void
end
EOF
      end

      worker.handle_job(Server::TypeCheckWorker::TypeCheckJob.new)
      worker_writer.write({ method: "close" })

      responses = reader.join.value
      responses.find {|resp| resp.dig(:params, :uri) =~ /\/lib\/hello\.rb/ }.tap do |resp|
        diagnostics = resp.dig(:params, :diagnostics)
        assert_equal ["Ruby::IncompatibleArguments"], diagnostics.map {|d| d[:code] }
      end
      responses.find {|resp| resp.dig(:params, :uri) =~ /\/sig\/hello\.rbs/ }.tap do |resp|
        diagnostics = resp.dig(:params, :diagnostics)
        assert_empty diagnostics
      end
    end
  end

  def test_job_workspace_symbol
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.parse(project, <<EOF)
target :lib do
  check "lib"
  signature "sig"
end
EOF

      worker = Server::TypeCheckWorker.new(
        project: project,
        assignment: assignment,
        commandline_args: [],
        reader: worker_reader,
        writer: worker_writer
      )

      worker.service.update(changes: {
        Pathname("sig/foo.rbs") => [ContentChange.string(<<RBS)]
class NewClassName
  def new_class_method: () -> void
end
RBS
      }) {}

      symbols = worker.workspace_symbol_result("")

      symbols.find {|symbol| symbol.name == "NewClassName" }.tap do |symbol|
        assert_equal "file://#{current_dir}/sig/foo.rbs", symbol.location[:uri].to_s
        assert_equal "", symbol.container_name
      end

      symbols.find {|symbol| symbol.name == "#new_class_method" }.tap do |symbol|
        assert_equal "file://#{current_dir}/sig/foo.rbs", symbol.location[:uri].to_s
        assert_equal "NewClassName", symbol.container_name
      end
    end
  end

  def test_loading_files_with_args
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.parse(project, <<EOF)
target :lib do
  check "lib"
  signature "sig"
end
EOF

      (current_dir + "lib").mkdir
      (current_dir + "lib/foo.rb").write("")
      (current_dir + "lib/bar.rb").write("")

      worker = Server::TypeCheckWorker.new(
        project: project,
        assignment: assignment,
        commandline_args: [],
        reader: worker_reader,
        writer: worker_writer
      )

      worker.load_files(project: worker.project, commandline_args: ["lib/foo.rb"])
      worker.service.update(changes: worker.pop_buffer) {}

      assert_equal [Pathname("lib/foo.rb")], worker.service.source_files.keys
    end
  end

  def test_job_stats
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.parse(project, <<RUBY)
target :lib do
  check "lib"
  signature "sig"
end
RUBY

      worker = Server::TypeCheckWorker.new(
        project: project,
        assignment: assignment,
        commandline_args: [],
        reader: worker_reader,
        writer: worker_writer
      )

      worker.service.update_and_check(
        changes: {
          Pathname("lib/hello.rb") => [Services::ContentChange.string(<<RUBY)],
Hello.new.world(10)
RUBY
          Pathname("lib/world.rb") => [Services::ContentChange.string(<<RUBY)]
1+
RUBY
        },
        assignment: assignment
      ) {}

      result = worker.stats_result()

      result.find {|stat| stat.path == Pathname("lib/hello.rb") }.tap do |stat|
        assert_instance_of Services::StatsCalculator::SuccessStats, stat
      end
      result.find {|stat| stat.path == Pathname("lib/world.rb") }.tap do |stat|
        assert_instance_of Services::StatsCalculator::ErrorStats, stat
      end
    end
  end
end
