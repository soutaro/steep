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

  def test_interaction_jobs_go_ahead_of_typecheck_jobs
    in_tmpdir do
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
          id: "typecheck",
          method: TypeCheck__File::METHOD,
          params: { guid: "guid", kind: "code", target: "lib", uri: "#{file_scheme}#{current_dir}/lib/hello.rb", content: "1 + true" }
        }
      )
      worker.handle_request(
        {
          id: "hover",
          method: Hover::METHOD,
          params: { uri: "#{file_scheme}#{current_dir}/lib/hello.rb", position: { line: 0, character: 0 } }
        }
      )
      worker.handle_request(
        {
          id: "symbol",
          method: Source__Symbol::METHOD,
          params: { uri: "#{file_scheme}#{current_dir}/lib/hello.rb", position: { line: 0, character: 0 } }
        }
      )

      # The interaction jobs come out before the type check job enqueued earlier, in their order
      jobs = flush_queue(worker.queue)
      assert_equal [TypeCheckWorker::HoverJob, TypeCheckWorker::SourceSymbolJob, TypeCheckWorker::TypeCheckCodeJob], jobs.map(&:class)
      assert_equal ["hover", "symbol", "typecheck"], jobs.map(&:id)
    end
  end

  def test_handle_job__latest_interaction_job_only
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

        worker.push_buffer do |buffer|
          buffer[Pathname("lib/foo.rb")] = [ContentChange.string("foo = 1\n")]
        end

        request_hover = -> (id) do
          worker.handle_request(
            {
              id: id,
              method: Hover::METHOD,
              params: { uri: "#{file_scheme}#{current_dir}/lib/foo.rb", position: { line: 0, character: 0 } }
            }
          )
        end

        request_hover["hover1"]
        request_hover["hover2"]
        job1, job2 = flush_queue(worker.queue)

        # The job enqueued before the latest one is answered with `nil`, without type checking
        worker.handle_job(job1)
        master_read_queue.pop.tap do |message|
          assert_equal "hover1", message[:id]
          assert_nil message[:result]
        end

        # The latest one is processed
        worker.handle_job(job2)
        master_read_queue.pop.tap do |message|
          assert_equal "hover2", message[:id]
          assert_equal({ kind: "variable", name: "foo", type: "::Integer" }, message[:result][:content])
        end

        # A source symbol job enqueued before a newer interaction job is answered with an empty result
        worker.handle_request(
          {
            id: "symbol",
            method: Source__Symbol::METHOD,
            params: { uri: "#{file_scheme}#{current_dir}/lib/foo.rb", position: { line: 0, character: 0 } }
          }
        )
        request_hover["hover3"]
        symbol_job, hover_job = flush_queue(worker.queue)

        worker.handle_job(symbol_job)
        master_read_queue.pop.tap do |message|
          assert_equal "symbol", message[:id]
          assert_equal({}, message[:result])
        end

        worker.handle_job(hover_job)
        master_read_queue.pop.tap do |message|
          assert_equal "hover3", message[:id]
          refute_nil message[:result]
        end
      end
    end
  end

  def test_handle_request_hover
    in_tmpdir do
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
          id: 123,
          method: Hover::METHOD,
          params: {
            uri: "#{file_scheme}#{current_dir}/lib/hello.rb",
            position: { line: 1, character: 2 }
          }
        }
      )

      q = flush_queue(worker.queue)
      assert_equal 1, q.size
      q[0].tap do |job|
        assert_instance_of TypeCheckWorker::HoverJob, job
        assert_equal 123, job.id
        assert_equal current_dir + "lib/hello.rb", job.path
        assert_equal 2, job.line
        assert_equal 2, job.column
      end
    end
  end

  def test_handle_source_symbol_request
    in_tmpdir do
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
          id: 123,
          method: Source__Symbol::METHOD,
          params: {
            uri: "#{file_scheme}#{current_dir}/lib/hello.rb",
            position: { line: 1, character: 2 }
          }
        }
      )

      q = flush_queue(worker.queue)
      assert_equal 1, q.size
      q[0].tap do |job|
        assert_instance_of TypeCheckWorker::SourceSymbolJob, job
        assert_equal current_dir + "lib/hello.rb", job.path
        assert_equal 2, job.line
        assert_equal 2, job.column
      end
    end
  end

  def test_process_source_symbol_job
    in_tmpdir do
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

      worker.service.update(
        changes: {
          Pathname("sig/customer.rbs") => [ContentChange.string(<<RBS)],
class Customer
  attr_accessor name: String
end
RBS
          Pathname("lib/main.rb") => [ContentChange.string(<<RUBY)]
customer = Customer.new()
customer.name = "Soutaro"
RUBY
        }
      )

      # `Customer` in `Customer.new()` -- the constant, and the type of the expression is its singleton
      result = worker.process_source_symbol(TypeCheckWorker::SourceSymbolJob.new(id: 1, path: current_dir + "lib/main.rb", line: 1, column: 14))
      assert_equal({ constant: "::Customer", type: "singleton(::Customer)" }, result)

      # `name` in `customer.name = ...` -- the method, and the type of the assignment is the value
      result = worker.process_source_symbol(TypeCheckWorker::SourceSymbolJob.new(id: 2, path: current_dir + "lib/main.rb", line: 2, column: 10))
      assert_equal({ method_names: ["::Customer#name="], type: "::String" }, result)

      # `customer` -- nothing is written, and the type of the variable is Customer
      result = worker.process_source_symbol(TypeCheckWorker::SourceSymbolJob.new(id: 3, path: current_dir + "lib/main.rb", line: 2, column: 2))
      assert_equal({ type: "::Customer" }, result)
    end
  end

  def test_handle_hover_job_success
    in_tmpdir do
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

      worker.service.update(
        changes: {
          Pathname("lib/foo.rb") => [ContentChange.string(<<RUBY)]
foo = 1 + 2
bar = foo.to_s
RUBY
        }
      ) {}

      response = worker.process_hover(TypeCheckWorker::HoverJob.new(path: current_dir + "lib/foo.rb", line: 1, column: 1))

      assert_equal(
        {
          target: "lib",
          range: { start: { line: 0, character: 0 }, end: { line: 0, character: 3 } },
          content: { kind: "variable", name: "foo", type: "::Integer" }
        },
        response
      )

      response = worker.process_hover(TypeCheckWorker::HoverJob.new(path: current_dir + "lib/foo.rb", line: 2, column: 11))

      assert_equal({ start: { line: 1, character: 10 }, end: { line: 1, character: 14 } }, response[:range])
      assert_equal(
        {
          kind: "method_call",
          return_type: "::String",
          special: false,
          error: false,
          method_types: ["(?::int base) -> ::String"],
          methods: ["::Integer#to_s"]
        },
        response[:content]
      )
    end
  end

  def test_handle_hover_job__definition_and_constant
    in_tmpdir do
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

      worker.service.update(
        changes: {
          Pathname("sig/foo.rbs") => [ContentChange.string(<<RBS)],
class Foo
  def self.bar: () -> Integer
end
RBS
          Pathname("lib/foo.rb") => [ContentChange.string(<<RUBY)]
class Foo
  def self.bar
    Foo
  end
end
RUBY
        }
      ) {}

      # `bar` in `def self.bar`
      response = worker.process_hover(TypeCheckWorker::HoverJob.new(path: current_dir + "lib/foo.rb", line: 2, column: 12))
      assert_equal(
        { kind: "definition", method: "::Foo.bar", method_type: "() -> ::Integer", method_types: ["() -> ::Integer"] },
        response[:content]
      )

      # `Foo` in the body
      response = worker.process_hover(TypeCheckWorker::HoverJob.new(path: current_dir + "lib/foo.rb", line: 3, column: 5))
      assert_equal({ kind: "constant", name: "::Foo" }, response[:content])
    end
  end

  def test_handle_hover_job__library_rbs
    in_tmpdir do
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

      worker.service.update(
        changes: {
          Pathname("sig/foo.rbs") => [ContentChange.string(<<RBS)]
class Foo
end
RBS
        }
      ) {}

      # A library RBS file is known by its absolute path, and belongs to the target that loads it
      path = RBS::EnvironmentLoader::DEFAULT_CORE_ROOT + "string.rbs"
      lines = path.read.lines
      line = lines.index {|text| text.include?("def =~: (Regexp regex) -> Integer?") } or raise
      column = lines[line].index("Integer") or raise

      response = worker.process_hover(TypeCheckWorker::HoverJob.new(path: path, line: line + 1, column: column + 2))

      assert_equal "lib", response[:target]
      assert_equal({ kind: "type_name", name: "::Integer" }, response[:content])

      # A file of no target is unknown
      assert_nil worker.process_hover(TypeCheckWorker::HoverJob.new(path: current_dir + "other/foo.rb", line: 1, column: 1))
    end
  end

  def test_handle_alias_hover_job_success_on_rbs
    in_tmpdir do
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

      response = worker.process_hover(TypeCheckWorker::HoverJob.new(path: current_dir + "sig/hello.rbs", line: 5, column: 11))

      assert_equal "lib", response[:target]
      assert_equal({ start: { line: 4, character: 10 }, end: { line: 4, character: 13 } }, response[:range])
      assert_equal({ kind: "type_name", name: "::foo" }, response[:content])
    end
  end

  def test_handle_interface_hover_job_success_on_rbs
    in_tmpdir do
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

      response = worker.process_hover(TypeCheckWorker::HoverJob.new(path: current_dir + "sig/hello.rbs", line: 7, column: 13))

      assert_equal({ start: { line: 6, character: 12 }, end: { line: 6, character: 20 } }, response[:range])
      assert_equal({ kind: "type_name", name: "::_Fooable" }, response[:content])
    end
  end

  def test_handle_class_hover_job_success_on_rbs
    in_tmpdir do
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

      response = worker.process_hover(TypeCheckWorker::HoverJob.new(path: current_dir + "sig/hello.rbs", line: 6, column: 10))

      assert_equal({ start: { line: 5, character: 8 }, end: { line: 5, character: 11 } }, response[:range])
      assert_equal({ kind: "type_name", name: "::Foo" }, response[:content])
    end
  end

  def test_handle_class_hover_strip_html_comment
    in_tmpdir do
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

      response = worker.process_hover(TypeCheckWorker::HoverJob.new(path: current_dir + "sig/hello.rbs", line: 5, column: 15))

      assert_equal({ start: { line: 4, character: 13 }, end: { line: 4, character: 16 } }, response[:range])
      assert_equal({ kind: "type_name", name: "::Foo" }, response[:content])
    end
  end

  def test_handle_hover_invalid
    in_tmpdir do
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

      worker.service.update(
        changes: {
          Pathname("lib/foo.rb") => [ContentChange.string(<<RUBY)]
foo = 1 + 2
bar = foo.
RUBY
        }
      ) {}

      response = worker.process_hover(TypeCheckWorker::HoverJob.new(path: current_dir + "lib/foo.rb", line: 1, column: 1))
      assert_nil response
    end
  end

  def test_handle_completion_request
    in_tmpdir do
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

      worker.service.update(
        changes: {
          Pathname("lib/hello.rb") => [ContentChange.string(<<RUBY)]
foo = 100
foo + "bar"
RUBY
        }
      ) {}

      response = worker.process_completion(
        TypeCheckWorker::CompletionJob.new(
          path: current_dir + "lib/hello.rb",
          line: 3,
          column: 0,
          trigger: nil
        )
      )

      assert_equal "lib", response[:target]
      refute response[:incomplete]
      assert_any!(response[:items]) do |item|
        assert_equal "method", item[:kind]
        assert_equal "puts", item[:name]
        assert_equal ["::Kernel#puts"], item[:methods]
        assert_equal ["(*::_ToS) -> nil"], item[:method_types]
        assert_equal({ start: { line: 2, character: 0 }, end: { line: 2, character: 0 } }, item[:range])
      end
    end
  end

  def test_handle_completion_request_inline
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.parse(project, <<~RUBY)
        target :lib do
          check "lib/inline.rb", inline: true
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

      worker.service.update(
        changes: {
          Pathname("lib/inline.rb") => [ContentChange.string(<<RUBY)]
class Foo
  # @rbs @name: String

  # @rbs () -> void
  def hello
    @name
  end
end
RUBY
        }
      ) {}

      response = worker.process_completion(
        TypeCheckWorker::CompletionJob.new(
          path: current_dir + "lib/inline.rb",
          line: 6,
          column: 5,
          trigger: nil
        )
      )

      assert_any!(response[:items]) do |item|
        assert_equal "instance_variable", item[:kind]
        assert_equal "@name", item[:name]
        assert_equal "::String", item[:type]
      end
    end
  end

  def test_completion_on_signature
    in_tmpdir do
      in_tmpdir do
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
          TypeCheckWorker::CompletionJob.new(
            path: current_dir + "sig/hello.rbs",
            line: 3,
            column: 9,
            trigger: nil
          )
        )

        assert_equal "lib", response[:target]
        refute response[:incomplete]

        assert_any!(response[:items]) do |item|
          assert_equal "type_name", item[:kind]
          assert_equal "Hash", item[:name]
          assert_equal "::Hash", item[:full_name]
          assert_equal({ start: { line: 2, character: 8 }, end: { line: 2, character: 9 } }, item[:range])
        end

        assert_any!(response[:items]) do |item|
          assert_equal "type_name", item[:kind]
          assert_equal "Hoge", item[:name]
          assert_equal "::Hoge", item[:full_name]
        end

        assert_any!(response[:items]) do |item|
          assert_equal "builtin_type", item[:kind]
          assert_equal "untyped", item[:name]
          assert_equal({ start: { line: 2, character: 8 }, end: { line: 2, character: 9 } }, item[:range])
        end
      end
    end
  end

  def test_signature_help
    in_tmpdir do
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

      worker.service.update(
        changes: {
          Pathname("sig/foo.rbs") => [ContentChange.string(<<RBS)],
class Foo
  def foo: (String name, ?Integer size) -> void
         | () -> void
end
RBS
          Pathname("lib/foo.rb") => [ContentChange.string(<<RUBY)]
Foo.new.foo("hello", 3)
RUBY
        }
      ) {}

      response = worker.process_signature_help(TypeCheckWorker::SignatureHelpJob.new(path: current_dir + "lib/foo.rb", line: 1, column: 21))

      refute response[:syntax_error]
      response[:signature_help].tap do |help|
        assert_equal "lib", help[:target]
        assert_equal 0, help[:active_signature]
        assert_equal(
          [
            { method_type: "(::String, ?::Integer) -> void", parameters: ["::String", "?::Integer"], active_parameter: 1, method: "::Foo#foo" },
            { method_type: "() -> void", parameters: [], active_parameter: -1, method: "::Foo#foo" }
          ],
          help[:signatures]
        )
      end

      # Outside of the arguments of a call
      response = worker.process_signature_help(TypeCheckWorker::SignatureHelpJob.new(path: current_dir + "lib/foo.rb", line: 1, column: 1))
      assert_equal({ signature_help: nil, syntax_error: false }, response)
    end
  end

  def test_signature_help__syntax_error
    in_tmpdir do
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

      worker.service.update(
        changes: {
          Pathname("lib/foo.rb") => [ContentChange.string(<<RUBY)]
foo(1,
RUBY
        }
      ) {}

      response = worker.process_signature_help(TypeCheckWorker::SignatureHelpJob.new(path: current_dir + "lib/foo.rb", line: 1, column: 6))
      assert_equal({ signature_help: nil, syntax_error: true }, response)
    end
  end
end
