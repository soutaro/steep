require_relative "test_helper"

# @rbs use Steep::*

class TypeCheckWorkerTest < Minitest::Test
  include TestHelper
  include ShellHelper
  include LSPTestHelper

  include Steep

  LSP = LanguageServer::Protocol::Interface

  TypeCheckWorker = Server::TypeCheckWorker
  ContentChange = Services::ContentChange

  include Server::CustomMethods

  def dirs
    @dirs ||= []
  end

  # @rbs (Server::TypeCheckWorker) { (Thread) -> void } -> void
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

  def assignment
    @assignment ||= Services::PathAssignment.all
  end

  def test_worker_exit
    in_tmpdir do
      with_master_read_queue do |master_read_queue|
        project = Project.new(steepfile_path: current_dir + "Steepfile")
        Project::DSL.parse(project, <<~RUBY)
          target :lib do
            check "lib"
            signature "sig"
          end
        RUBY

        run_worker(
          Server::TypeCheckWorker.new(
            project: project,
            assignment: assignment,
            commandline_args: [],
            reader: worker_reader,
            writer: worker_writer)
        ) do |worker|
          # The worker stops at `exit`, without a `shutdown` request
          master_writer.write(
            method: :exit
          )
        end
      end
    end
  end

  def test_handle_request_initialize
    in_tmpdir do
      with_master_read_queue do
        project = Project.new(steepfile_path: current_dir + "Steepfile")
        Project::DSL.parse(project, <<~RUBY)
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
  end

  def test_handle_request_file_load
    in_tmpdir do
      with_master_read_queue do
        project = Project.new(steepfile_path: current_dir + "Steepfile")
        Project::DSL.parse(project, <<~RUBY)
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

        worker.handle_request(
          {
            method: FileLoad::METHOD,
            params: {
              content: { "lib/hello.rb" => "class Foo\nend\n" }
            }
          }
        )

        jobs = flush_queue(worker.queue)
        assert_empty jobs

        changes = worker.pop_buffer
        assert_equal({ Pathname("lib/hello.rb") => [Services::ContentChange.string("class Foo\nend\n")] }, changes)
      end
    end
  end

  def test_handle_request_typecheck_file
    in_tmpdir do
      with_master_read_queue do
        project = Project.new(steepfile_path: current_dir + "Steepfile")
        Project::DSL.parse(project, <<~RUBY)
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

        # A request with the content of the file buffers the content and enqueues the job
        worker.handle_request(
          {
            id: "request-1",
            method: TypeCheck__File::METHOD,
            params: {
              guid: "guid1",
              kind: "code",
              target: "lib",
              uri: "#{file_scheme}#{current_dir}/lib/hello.rb",
              content: "class Foo\nend\n"
            }
          }
        )
        worker.handle_request(
          {
            id: "request-2",
            method: TypeCheck__File::METHOD,
            params: { guid: "guid1", kind: "signature", target: "lib", uri: "#{file_scheme}#{current_dir}/sig/hello.rbs" }
          }
        )
        worker.handle_request(
          {
            id: "request-3",
            method: TypeCheck__File::METHOD,
            params: { guid: "guid1", kind: "library", target: "lib", uri: "#{file_scheme}#{RBS::EnvironmentLoader::DEFAULT_CORE_ROOT + "object.rbs"}" }
          }
        )

        jobs = flush_queue(worker.queue)
        assert_equal 3, jobs.size

        jobs[0].tap do |job|
          assert_instance_of TypeCheckWorker::TypeCheckCodeJob, job
          assert_equal "request-1", job.id
          assert_equal current_dir + "lib/hello.rb", job.path
        end
        jobs[1].tap do |job|
          assert_instance_of TypeCheckWorker::ValidateAppSignatureJob, job
          assert_equal "request-2", job.id
          assert_equal current_dir + "sig/hello.rbs", job.path
        end
        jobs[2].tap do |job|
          assert_instance_of TypeCheckWorker::ValidateLibrarySignatureJob, job
          assert_equal "request-3", job.id
          assert_equal RBS::EnvironmentLoader::DEFAULT_CORE_ROOT + "object.rbs", job.path
        end

        assert_equal({ Pathname("lib/hello.rb") => [Services::ContentChange.string("class Foo\nend\n")] }, worker.pop_buffer)
      end
    end
  end

  def test_handle_job_validate_app_signature
    in_tmpdir do
      with_master_read_queue do |master_read_queue|
        project = Project.new(steepfile_path: current_dir + "Steepfile")
        Project::DSL.parse(project, <<~RUBY)
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

        {}.tap do |changes|
          changes[Pathname("lib/hello.rb")] = [Services::ContentChange.string(<<~RUBY)]
            Hello.new.world(10)
          RUBY
          changes[Pathname("sig/hello.rbs")] = [Services::ContentChange.string(<<~RBS)]
            class Hello
              def world: () -> void
            end
          RBS
          worker.push_buffer { |buffer| buffer.merge!(changes) }
        end

        job = TypeCheckWorker::ValidateAppSignatureJob.new(id: "guid", path: current_dir + "sig/hello.rbs", target: project.targets[0])
        worker.handle_job(job)

        master_read_queue.pop.tap do |message|
          assert_equal "guid", message[:id]
          assert_empty message[:result][:signature][:diagnostics]
        end
      end
    end
  end

  def test_handle_job_validate_app_signature_entries
    in_tmpdir do
      with_master_read_queue do |master_read_queue|
        project = Project.new(steepfile_path: current_dir + "Steepfile")
        Project::DSL.parse(project, <<~RUBY)
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

        {}.tap do |changes|
          changes[Pathname("sig/hello.rbs")] = [Services::ContentChange.string(<<~RBS)]
            class Hello
              def world: () -> void
              attr_reader name: String
              alias greet world
            end

            interface _Greeter
              def greet: () -> void
            end

            type greeting = String

            VERSION: String

            $hello: Hello
          RBS
          worker.push_buffer { |buffer| buffer.merge!(changes) }
        end

        job = TypeCheckWorker::ValidateAppSignatureJob.new(id: "guid", path: current_dir + "sig/hello.rbs", target: project.targets[0])
        worker.handle_job(job)

        master_read_queue.pop.tap do |message|
          assert_equal "guid", message[:id]
          assert_empty message[:result][:signature][:diagnostics]

          entries = message[:result][:signature][:entries]

          # Class, methods (`def`, `attr_reader`, and `alias`)
          assert_includes entries, ["::Hello", 0, 0, 6, 0, 11]
          assert_includes entries, ["::Hello#world", 0, 1, 6, 1, 11]
          assert_includes entries, ["::Hello#name", 0, 2, 14, 2, 18]
          assert_includes entries, ["::Hello#greet", 0, 3, 8, 3, 13]

          # Interface, type alias, constant, and global
          assert_includes entries, ["::_Greeter", 0, 6, 10, 6, 18]
          assert_includes entries, ["::_Greeter#greet", 0, 7, 6, 7, 11]
          assert_includes entries, ["::greeting", 0, 10, 5, 10, 13]
          assert_includes entries, ["::VERSION", 0, 12, 0, 12, 7]
          assert_includes entries, ["$hello", 0, 14, 0, 14, 6]

          # References to the types written in the file, including the ones declared in other files
          assert_includes entries, ["::String", 1, 2, 20, 2, 26]
          assert_includes entries, ["::Hello#world", 1, 3, 14, 3, 19]
          assert_includes entries, ["::String", 1, 10, 16, 10, 22]
          assert_includes entries, ["::String", 1, 12, 9, 12, 15]
          assert_includes entries, ["::Hello", 1, 14, 8, 14, 13]

          # Declarations of other files are not included
          refute entries.any? {|name, role, *| name == "::String" && role == 0 }
        end
      end
    end
  end

  def test_handle_job_validate_app_signature_entries_on_syntax_error
    in_tmpdir do
      with_master_read_queue do |master_read_queue|
        project = Project.new(steepfile_path: current_dir + "Steepfile")
        Project::DSL.parse(project, <<~RUBY)
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

        {}.tap do |changes|
          changes[Pathname("sig/hello.rbs")] = [Services::ContentChange.string(<<~RBS)]
            class Hello
              def world: () ->
          RBS
          worker.push_buffer { |buffer| buffer.merge!(changes) }
        end

        job = TypeCheckWorker::ValidateAppSignatureJob.new(id: "guid", path: current_dir + "sig/hello.rbs", target: project.targets[0])
        worker.handle_job(job)

        master_read_queue.pop.tap do |message|
          assert_equal "guid", message[:id]
          refute_empty message[:result][:signature][:diagnostics]

          # No entries are reported while the signatures fail to load
          assert_nil message[:result][:signature][:entries]
          assert_nil message[:result][:signature][:stats]
        end
      end
    end
  end

  def test_handle_job_validate_lib_signature
    in_tmpdir do
      with_master_read_queue do |master_read_queue|
        project = Project.new(steepfile_path: current_dir + "Steepfile")
        Project::DSL.parse(project, <<~RUBY)
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

        {}.tap do |changes|
          changes[Pathname("lib/hello.rb")] = [Services::ContentChange.string(<<~RUBY)]
            Hello.new.world(10)
          RUBY
          changes[Pathname("sig/hello.rbs")] = [Services::ContentChange.string(<<~RBS)]
            class Hello
              def world: () -> void
            end
          RBS
          worker.push_buffer { |buffer| buffer.merge!(changes) }
        end

        job = TypeCheckWorker::ValidateLibrarySignatureJob.new(
          id: "guid",
          path: RBS::EnvironmentLoader::DEFAULT_CORE_ROOT + "object.rbs",
          target: project.targets[0]
        )
        worker.handle_job(job)

        master_read_queue.deq.tap do |message|
          assert_equal "guid", message[:id]
          assert_empty message[:result][:signature][:diagnostics]
        end
      end
    end
  end

  def test_handle_job_typecheck_code
    in_tmpdir do
      with_master_read_queue do |master_read_queue|
        project = Project.new(steepfile_path: current_dir + "Steepfile")
        Project::DSL.parse(project, <<~RUBY)
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

        {}.tap do |changes|
          changes[Pathname("lib/hello.rb")] = [Services::ContentChange.string(<<~RUBY)]
            Hello.new.world(10)
          RUBY
          changes[Pathname("sig/hello.rbs")] = [Services::ContentChange.string(<<~RUBY)]
            class Hello
              def world: () -> void
            end
          RUBY
          worker.push_buffer { |buffer| buffer.merge!(changes) }
        end

        job = TypeCheckWorker::TypeCheckCodeJob.new(id: "guid", path: current_dir + "lib/hello.rb", target: project.targets[0])
        worker.handle_job(job)

        master_read_queue.pop.tap do |message|
          assert_equal "guid", message[:id]
          assert_equal 1, message[:result][:source][:diagnostics].size
        end
      end
    end
  end

  def test_handle_job_typecheck_code_entries
    in_tmpdir do
      with_master_read_queue do |master_read_queue|
        project = Project.new(steepfile_path: current_dir + "Steepfile")
        Project::DSL.parse(project, <<~RUBY)
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

        {}.tap do |changes|
          changes[Pathname("lib/hello.rb")] = [Services::ContentChange.string(<<~RUBY)]
            class Hello
              def world
              end
            end

            Hello.new.world()
          RUBY
          changes[Pathname("sig/hello.rbs")] = [Services::ContentChange.string(<<~RUBY)]
            class Hello
              def world: () -> void
            end
          RUBY
          worker.push_buffer { |buffer| buffer.merge!(changes) }
        end

        job = TypeCheckWorker::TypeCheckCodeJob.new(id: "guid", path: current_dir + "lib/hello.rb", target: project.targets[0])
        worker.handle_job(job)

        master_read_queue.pop.tap do |message|
          assert_equal "guid", message[:id]

          entries = message[:result][:source][:entries]

          # Constant definition and reference of ::Hello
          assert_includes entries, ["::Hello", 0, 0, 6, 0, 11]
          assert_includes entries, ["::Hello", 1, 5, 0, 5, 5]

          # Method definition and reference of ::Hello#world
          assert_includes entries, ["::Hello#world", 0, 1, 6, 1, 11]
          assert_includes entries, ["::Hello#world", 1, 5, 10, 5, 15]

          # The reference of `.new` points at the selector
          assert(entries.any? {|_, role, line, character, _, _| role == 1 && line == 5 && character == 6 })

          # The method calls are counted for `$/steep/stats`
          assert_equal({ typed_calls: 2, untyped_calls: 0, error_calls: 0 }, message[:result][:source][:stats])

          # The worker keeps the content of the file only
          assert_nil worker.service.source_files[Pathname("lib/hello.rb")].typing
        end
      end
    end
  end

  def test_handle_job_typecheck_code_diagnostics
    in_tmpdir do
      with_master_read_queue do |master_read_queue|
        project = Project.new(steepfile_path: current_dir + "Steepfile")
        Project::DSL.parse(project, <<~RUBY)
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
        RUBY

        worker = Server::TypeCheckWorker.new(
          project: project,
          assignment: assignment,
          commandline_args: [],
          reader: worker_reader,
          writer: worker_writer
        )

        {}.tap do |changes|
          changes[Pathname("lib/hello.rb")] = [Services::ContentChange.string(<<~RUBY)]
            Hello.new.world(10)
            UnKnownConStant = 123
            "hello".world()
          RUBY
          changes[Pathname("sig/hello.rbs")] = [Services::ContentChange.string(<<~RBS)]
            class Hello
              def world: () -> void
            end
          RBS
          worker.push_buffer { |buffer| buffer.merge!(changes) }
        end

        job = TypeCheckWorker::TypeCheckCodeJob.new(id: "guid", path: current_dir + "lib/hello.rb", target: project.targets[0])
        worker.handle_job(job)

        master_read_queue.pop.tap do |message|
          assert_equal "guid", message[:id]

          assert_any!(message[:result][:source][:diagnostics], size: 2) do |diagnostic|
            assert_equal "Ruby::UnexpectedPositionalArgument", diagnostic[:code]
            assert_equal 1, diagnostic[:severity]
          end

          assert_any!(message[:result][:source][:diagnostics], size: 2) do |diagnostic|
            assert_equal "Ruby::UnknownConstant", diagnostic[:code]
            assert_equal 3, diagnostic[:severity]
          end
        end
      end
    end
  end

  def test_handle_job_typecheck_inline__no_error
    in_tmpdir do
      with_master_read_queue do |master_read_queue|
        project = Project.new(steepfile_path: current_dir + "Steepfile")
        Project::DSL.eval(project) do
          target :lib do
            check "lib", inline: true
            signature "sig"
          end
        end

        worker = Server::TypeCheckWorker.new(
          project: project,
          assignment: assignment,
          commandline_args: [],
          reader: worker_reader,
          writer: worker_writer
        )

        {}.tap do |changes|
          changes[Pathname("lib/hello.rb")] = [Services::ContentChange.string(<<~RUBY)]
            class Hello
              # @rbs (Integer) -> String
              def world(x)
                x.to_s
              end
            end
            Hello.new.world(10)
          RUBY
          worker.push_buffer { |buffer| buffer.merge!(changes) }
        end

        job = TypeCheckWorker::TypeCheckInlineCodeJob.new(id: "guid", path: current_dir + "lib/hello.rb", target: project.targets[0])
        worker.handle_job(job)

        master_read_queue.pop.tap do |message|
          assert_equal "guid", message[:id]
          assert_equal 0, message[:result][:source][:diagnostics].size
        end
      end
    end
  end

  def test_handle_job_typecheck_inline__implementation_error
    in_tmpdir do
      with_master_read_queue do |master_read_queue|
        project = Project.new(steepfile_path: current_dir + "Steepfile")
        Project::DSL.eval(project) do
          target :lib do
            check "lib", inline: true
            signature "sig"
          end
        end

        worker = Server::TypeCheckWorker.new(
          project: project,
          assignment: assignment,
          commandline_args: [],
          reader: worker_reader,
          writer: worker_writer
        )

        {}.tap do |changes|
          changes[Pathname("lib/hello.rb")] = [Services::ContentChange.string(<<~RUBY)]
            class Hello
              # @rbs (Integer) -> String
              def world(x)
                x.to_s
              end
            end
            Hello.new.world("10")
          RUBY
          worker.push_buffer { |buffer| buffer.merge!(changes) }
        end

        job = TypeCheckWorker::TypeCheckInlineCodeJob.new(id: "guid", path: current_dir + "lib/hello.rb", target: project.targets[0])
        worker.handle_job(job)

        master_read_queue.pop.tap do |message|
          assert_equal "guid", message[:id]
          assert_equal 1, message[:result][:source][:diagnostics].size
          assert_equal "Ruby::ArgumentTypeMismatch", message[:result][:source][:diagnostics][0][:code]
        end
      end
    end
  end

  def test_handle_job_typecheck_inline__type_decl_error
    in_tmpdir do
      with_master_read_queue do |master_read_queue|
        project = Project.new(steepfile_path: current_dir + "Steepfile")
        Project::DSL.eval(project) do
          target :lib do
            check "lib", inline: true
            signature "sig"
          end
        end

        worker = Server::TypeCheckWorker.new(
          project: project,
          assignment: assignment,
          commandline_args: [],
          reader: worker_reader,
          writer: worker_writer
        )

        {}.tap do |changes|
          changes[Pathname("lib/hello.rb")] = [Services::ContentChange.string(<<~RUBY)]
            class Hello
              # @rbs (Integer) ->
              def world(x)
                x.to_s
              end
            end
            Hello.new.world(10)
          RUBY
          worker.push_buffer { |buffer| buffer.merge!(changes) }
        end

        job = TypeCheckWorker::TypeCheckInlineCodeJob.new(id: "guid", path: current_dir + "lib/hello.rb", target: project.targets[0])
        worker.handle_job(job)

        master_read_queue.pop.tap do |message|
          assert_equal "guid", message[:id]
          assert_equal 1, message[:result][:signature][:diagnostics].size
          pp message[:result][:signature][:diagnostics][0]
          assert_equal "RBS::InlineDiagnostic", message[:result][:signature][:diagnostics][0][:code]
        end
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
end
