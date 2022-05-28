require_relative "test_helper"

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
              uri: "#{file_scheme}#{current_dir}/lib/hello.rb"
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
      worker.load_files(project: worker.project, commandline_args: [])

      worker.handle_request(
        {
          method: "$/typecheck/start",
          params: {
            guid: "guid1",
            priority_uris: ["#{file_scheme}#{current_dir}/lib/hello.rb"],
            signature_uris: ["#{file_scheme}#{current_dir}/sig/hello.rbs"],
            code_uris: ["#{file_scheme}#{current_dir}/lib/hello.rb"],
            library_uris: ["#{file_scheme}#{RBS::EnvironmentLoader::DEFAULT_CORE_ROOT + "object.rbs"}"]
          }
        }
      )

      jobs = flush_queue(worker.queue)
      assert_equal 4, jobs.size

      assert_equal "guid1", worker.current_type_check_guid

      jobs[0].tap do |job|
        assert_instance_of TypeCheckWorker::StartTypeCheckJob, job
        assert_equal "guid1", job.guid
      end

      assert_any!(jobs) do |job|
        assert_instance_of TypeCheckWorker::ValidateAppSignatureJob, job
        assert_equal "guid1", job.guid
        assert_equal current_dir + "sig/hello.rbs", job.path
      end

      assert_any!(jobs) do |job|
        assert_instance_of TypeCheckWorker::ValidateLibrarySignatureJob, job
        assert_equal "guid1", job.guid
        assert_equal RBS::EnvironmentLoader::DEFAULT_CORE_ROOT + "object.rbs", job.path
      end

      assert_any!(jobs) do |job|
        assert_instance_of TypeCheckWorker::TypeCheckCodeJob, job
        assert_equal "guid1", job.guid
        assert_equal current_dir + "lib/hello.rb", job.path
      end
    end
  end

  def test_handle_job_start_typecheck
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
      worker.load_files(project: worker.project, commandline_args: [])

      changes = {}
      changes[Pathname("lib/hello.rb")] = [Services::ContentChange.string(<<EOF)]
Hello.new.world(10)
EOF
      changes[Pathname("sig/hello.rbs")] = [Services::ContentChange.string(<<EOF)]
class Hello
  def world: () -> void
end
EOF
      job = TypeCheckWorker::StartTypeCheckJob.new(guid: "guid", changes: changes)

      # StartTypeCheckJob applies buffered changes to TypeCheckService
      worker.handle_job(job)

      assert_equal <<RUBY, worker.service.source_files[Pathname("lib/hello.rb")].content
Hello.new.world(10)
RUBY
      assert_equal <<RBS, worker.service.signature_services[:lib].files[Pathname("sig/hello.rbs")].content
class Hello
  def world: () -> void
end
RBS
    end
  end

  def test_handle_job_validate_app_signature
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

      worker.load_files(project: worker.project, commandline_args: [])
      worker.instance_variable_set(:@current_type_check_guid, "guid")

      {}.tap do |changes|
        changes[Pathname("lib/hello.rb")] = [Services::ContentChange.string(<<EOF)]
Hello.new.world(10)
EOF
        changes[Pathname("sig/hello.rbs")] = [Services::ContentChange.string(<<EOF)]
class Hello
  def world: () -> void
end
EOF
        worker.handle_job(TypeCheckWorker::StartTypeCheckJob.new(guid: "guid", changes: changes))
      end

      job = TypeCheckWorker::ValidateAppSignatureJob.new(guid: "guid", path: current_dir + "sig/hello.rbs")
      worker.handle_job(job)

      master_reader.read {|response| break response }.tap do |message|
        assert_equal "textDocument/publishDiagnostics", message[:method]
        assert_equal "#{file_scheme}#{current_dir + "sig/hello.rbs"}", message[:params][:uri]
      end

      master_reader.read {|response| break response }.tap do |message|
        assert_equal "$/typecheck/progress", message[:method]
        assert_equal "guid", message[:params][:guid]
        assert_equal (current_dir + "sig/hello.rbs").to_s, message[:params][:path]
      end
    end
  end

  def test_handle_job_validate_app_signature_skip
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

      worker.load_files(project: worker.project, commandline_args: [])
      worker.instance_variable_set(:@current_type_check_guid, nil)

      {}.tap do |changes|
        changes[Pathname("lib/hello.rb")] = [Services::ContentChange.string(<<EOF)]
Hello.new.world(10)
EOF
        changes[Pathname("sig/hello.rbs")] = [Services::ContentChange.string(<<EOF)]
class Hello
  def world: () -> void
end
EOF
        worker.handle_job(TypeCheckWorker::StartTypeCheckJob.new(guid: "guid", changes: changes))
      end

      job = TypeCheckWorker::ValidateAppSignatureJob.new(guid: "guid", path: current_dir + "sig/hello.rbs")
      worker.handle_job(job)

      # handle_job doesn't write anything because the #current_type_check_guid is different.
      worker.writer.write({ method: "sentinel"})
      master_reader.read {|response| break response }.tap do |message|
        assert_equal "sentinel", message[:method]
      end
    end
  end

  def test_handle_job_validate_lib_signature
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

      worker.load_files(project: worker.project, commandline_args: [])
      worker.instance_variable_set(:@current_type_check_guid, "guid")

      {}.tap do |changes|
        changes[Pathname("lib/hello.rb")] = [Services::ContentChange.string(<<EOF)]
Hello.new.world(10)
EOF
        changes[Pathname("sig/hello.rbs")] = [Services::ContentChange.string(<<EOF)]
class Hello
  def world: () -> void
end
EOF
        worker.handle_job(TypeCheckWorker::StartTypeCheckJob.new(guid: "guid", changes: changes))
      end

      job = TypeCheckWorker::ValidateLibrarySignatureJob.new(
        guid: "guid",
        path: RBS::EnvironmentLoader::DEFAULT_CORE_ROOT + "object.rbs"
      )
      worker.handle_job(job)

      master_reader.read {|response| break response }.tap do |message|
        assert_equal "textDocument/publishDiagnostics", message[:method]
        assert_equal "#{file_scheme}#{RBS::EnvironmentLoader::DEFAULT_CORE_ROOT + "object.rbs"}", message[:params][:uri]
      end

      master_reader.read {|response| break response }.tap do |message|
        assert_equal "$/typecheck/progress", message[:method]
        assert_equal "guid", message[:params][:guid]
        assert_equal (RBS::EnvironmentLoader::DEFAULT_CORE_ROOT + "object.rbs").to_s, message[:params][:path]
      end
    end
  end

  def test_handle_job_validate_lib_signature_skip
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

      worker.load_files(project: worker.project, commandline_args: [])
      worker.instance_variable_set(:@current_type_check_guid, nil)

      {}.tap do |changes|
        changes[Pathname("lib/hello.rb")] = [Services::ContentChange.string(<<EOF)]
Hello.new.world(10)
EOF
        changes[Pathname("sig/hello.rbs")] = [Services::ContentChange.string(<<EOF)]
class Hello
  def world: () -> void
end
EOF
        worker.handle_job(TypeCheckWorker::StartTypeCheckJob.new(guid: "guid", changes: changes))
      end

      job = TypeCheckWorker::ValidateLibrarySignatureJob.new(
        guid: "guid",
        path: RBS::EnvironmentLoader::DEFAULT_CORE_ROOT + "object.rbs"
      )

      # handle_job doesn't write anything because the #current_type_check_guid is different.
      worker.writer.write({ method: "sentinel"})
      master_reader.read {|response| break response }.tap do |message|
        assert_equal "sentinel", message[:method]
      end
    end
  end

  def test_handle_job_typecheck_code
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

      worker.load_files(project: worker.project, commandline_args: [])
      worker.instance_variable_set(:@current_type_check_guid, "guid")

      {}.tap do |changes|
        changes[Pathname("lib/hello.rb")] = [Services::ContentChange.string(<<EOF)]
Hello.new.world(10)
EOF
        changes[Pathname("sig/hello.rbs")] = [Services::ContentChange.string(<<EOF)]
class Hello
  def world: () -> void
end
EOF
        worker.handle_job(TypeCheckWorker::StartTypeCheckJob.new(guid: "guid", changes: changes))
      end

      job = TypeCheckWorker::TypeCheckCodeJob.new(guid: "guid", path: current_dir + "lib/hello.rb")
      worker.handle_job(job)

      master_reader.read {|response| break response }.tap do |message|
        assert_equal "textDocument/publishDiagnostics", message[:method]
        assert_equal "#{file_scheme}#{current_dir + "lib/hello.rb"}", message[:params][:uri]
      end

      master_reader.read {|response| break response }.tap do |message|
        assert_equal "$/typecheck/progress", message[:method]
        assert_equal "guid", message[:params][:guid]
        assert_equal (current_dir + "lib/hello.rb").to_s, message[:params][:path]
      end
    end
  end

  def test_handle_job_typecheck_code_diagnostics
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.parse(project, <<EOF)
D = Steep::Diagnostic

target :lib do
  check "lib"
  signature "sig"

  configure_code_diagnostics do |hash|
    hash[D::Ruby::UnexpectedPositionalArgument] = :error
    hash[D::Ruby::UnknownConstant] = :information
    hash[D::Ruby::NoMethod] = nil
  end
end
EOF

      worker = Server::TypeCheckWorker.new(
        project: project,
        assignment: assignment,
        commandline_args: [],
        reader: worker_reader,
        writer: worker_writer
      )

      worker.load_files(project: worker.project, commandline_args: [])
      worker.instance_variable_set(:@current_type_check_guid, "guid")

      {}.tap do |changes|
        changes[Pathname("lib/hello.rb")] = [Services::ContentChange.string(<<EOF)]
Hello.new.world(10)
UnKnownConStant = 123
"hello".world()
EOF
        changes[Pathname("sig/hello.rbs")] = [Services::ContentChange.string(<<EOF)]
class Hello
  def world: () -> void
end
EOF
        worker.handle_job(TypeCheckWorker::StartTypeCheckJob.new(guid: "guid", changes: changes))
      end

      job = TypeCheckWorker::TypeCheckCodeJob.new(guid: "guid", path: current_dir + "lib/hello.rb")
      worker.handle_job(job)

      message = master_reader.read do |response|
        if response[:method] == "textDocument/publishDiagnostics" &&
          response[:params][:uri] == "#{file_scheme}#{current_dir + "lib/hello.rb"}"
          break response
        end
      end

      assert_instance_of Hash, message

      assert_any!(message[:params][:diagnostics], size: 2) do |diagnostic|
        assert_equal "Ruby::UnexpectedPositionalArgument", diagnostic[:code]
        assert_equal 1, diagnostic[:severity]
      end

      assert_any!(message[:params][:diagnostics], size: 2) do |diagnostic|
        assert_equal "Ruby::UnknownConstant", diagnostic[:code]
        assert_equal 3, diagnostic[:severity]
      end
    end
  end

  def test_handle_job_validate_lib_signature_skip
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

      worker.load_files(project: worker.project, commandline_args: [])
      worker.instance_variable_set(:@current_type_check_guid, nil)

      {}.tap do |changes|
        changes[Pathname("lib/hello.rb")] = [Services::ContentChange.string(<<EOF)]
Hello.new.world(10)
EOF
        changes[Pathname("sig/hello.rbs")] = [Services::ContentChange.string(<<EOF)]
class Hello
  def world: () -> void
end
EOF
        worker.handle_job(TypeCheckWorker::StartTypeCheckJob.new(guid: "guid", changes: changes))
      end

      job = TypeCheckWorker::TypeCheckCodeJob.new(guid: "guid", path: current_dir + "lib/hello.rb")

      # handle_job doesn't write anything because the #current_type_check_guid is different.
      worker.writer.write({ method: "sentinel"})
      master_reader.read {|response| break response }.tap do |message|
        assert_equal "sentinel", message[:method]
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
        assert_equal "#{file_scheme}#{current_dir}/sig/foo.rbs", symbol.location[:uri].to_s
        assert_equal "", symbol.container_name
      end

      symbols.find {|symbol| symbol.name == "#new_class_method" }.tap do |symbol|
        assert_equal "#{file_scheme}#{current_dir}/sig/foo.rbs", symbol.location[:uri].to_s
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

  def test_goto_definition_from_ruby
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.parse(project, <<RUBY)
target :lib do
  check "lib"
  signature "sig"
end
RUBY

      worker = TypeCheckWorker.new(
        project: project,
        assignment: assignment,
        commandline_args: [],
        reader: worker_reader,
        writer: worker_writer
      )

      worker.service.update(
        changes: {
          Pathname("sig/customer.rbs") => [Services::ContentChange.string(<<RBS)],
class Customer
  attr_accessor name: String
end
RBS
          Pathname("lib/main.rb") => [Services::ContentChange.string(<<RUBY)],
customer = Customer.new()
customer.name = "Soutaro"
RUBY
        }
      )

      TypeCheckWorker::GotoJob.definition(
        id: Time.now.to_i,
        params: {
          textDocument: { uri: "#{file_scheme}#{current_dir}/lib/main.rb" },
          position: { line: 0, character: 14 }
        }
      ).tap do |job|
        worker.goto(job).tap do |locations|
          assert_any!(locations, size: 1) do |loc|
            assert_equal "#{file_scheme}#{current_dir}/sig/customer.rbs", loc[:uri]
            assert_equal(
              {
                start: { line: 0, character: 6 },
                end: { line: 0, character: 14 }
              },
              loc[:range]
            )
          end
        end
      end

      TypeCheckWorker::GotoJob.implementation(
        id: Time.now.to_i,
        params: {
          textDocument: { uri: "#{file_scheme}#{current_dir}/lib/main.rb" },
          position: { line: 0, character: 14 }
        }
      ).tap do |job|
        worker.goto(job).tap do |locations|
          assert_empty locations
        end
      end
    end
  end
end
