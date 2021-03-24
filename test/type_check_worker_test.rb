require "test_helper"

class TypeCheckWorkerTest < Minitest::Test
  include TestHelper
  include ShellHelper
  include LSPTestHelper

  include Steep

  LSP = LanguageServer::Protocol::Interface

  TypeCheckWorker = Server::TypeCheckWorker
  ContentChange = Services::ContentChange

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

  def test_handle_request_initialize
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
      assert_empty jobs
    end
  end

  def test_handle_request_document_did_change
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
      assert_empty jobs

      changes = worker.pop_buffer
      assert_equal({ Pathname("lib/hello.rb") => [Services::ContentChange.string("class Foo\nend\n")] }, changes)
    end
  end

  def test_handle_request_typecheck_start
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
          id: 123,
          method: "$/typecheck/start",
          params: {
            guid: "guid1",
            priority_uris: ["file://#{current_dir}/lib/hello.rb"],
            signature_uris: ["file://#{current_dir}/sig/hello.rbs"],
            code_uris: ["file://#{current_dir}/lib/hello.rb"],
            library_uris: ["file://#{(RBS::EnvironmentLoader::DEFAULT_CORE_ROOT + "object.rbs")}"]
          }
        }
      )

      jobs = flush_queue(worker.queue)
      assert_equal 1, jobs.size

      jobs[0].tap do |job|
        assert_instance_of TypeCheckWorker::TypeCheckJob, job
        assert_equal 123, job.request_id
        assert_equal Set[current_dir + "lib/hello.rb"], job.priority_paths
        assert_equal [current_dir + "sig/hello.rbs"], job.signature_paths
        assert_equal [current_dir + "lib/hello.rb"], job.code_paths
        assert_equal [RBS::EnvironmentLoader::DEFAULT_CORE_ROOT + "object.rbs"], job.library_paths
      end
    end
  end

  def test_run_typecheck
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

      job = TypeCheckWorker::TypeCheckJob.new(
        guid: "guid",
        priority_paths: Set[],
        signature_paths: [current_dir + "sig/hello.rbs"],
        code_paths: [current_dir + "lib/hello.rb"],
        library_paths: [RBS::EnvironmentLoader::DEFAULT_CORE_ROOT + "object.rbs"]
      )

      diagnostics = []
      worker.run_typecheck(job) do |path, ds|
        diagnostics << [path, ds]
      end

      assert_any!(diagnostics) do |(path, ds)|
        assert_equal RBS::EnvironmentLoader::DEFAULT_CORE_ROOT + "object.rbs", path
        assert_empty ds
      end

      assert_any!(diagnostics) do |(path, ds)|
        assert_equal Pathname("sig/hello.rbs"), path
        assert_empty ds
      end

      assert_any!(diagnostics) do |(path, ds)|
        assert_equal Pathname("lib/hello.rb"), path
        assert_equal 1, ds.size
        assert_instance_of Diagnostic::Ruby::IncompatibleArguments, ds[0]
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
