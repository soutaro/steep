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

  # Returns the wire entries as `[name, kind (or role without kind), start_line, start_character, end_line, end_character]`
  def summarize_entries(entries) #: Array[Array[untyped]]
    entries.map do |wire|
      entry = Server::TypeCheckDatabase::Entry.from_wire(wire)
      [entry.name, entry.kind || entry.role, entry.start_line, entry.start_character, entry.end_line, entry.end_character]
    end
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
        worker.handle_request(
          {
            id: "request-4",
            method: TypeCheck__File::METHOD,
            params: { guid: "index", kind: "index", target: "lib", uri: "#{file_scheme}#{current_dir}/sig/hello.rbs" }
          }
        )

        jobs = flush_queue(worker.queue)
        assert_equal 4, jobs.size

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
        jobs[3].tap do |job|
          assert_instance_of TypeCheckWorker::IndexSignatureJob, job
          assert_equal "request-4", job.id
          assert_equal current_dir + "sig/hello.rbs", job.path
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

          entries = summarize_entries(message[:result][:signature][:entries])

          # Class, methods (`def`, `attr_reader`, and `alias`)
          assert_includes entries, ["::Hello", :class, 0, 6, 0, 11]
          assert_includes entries, ["::Hello#world", :method, 1, 6, 1, 11]
          assert_includes entries, ["::Hello#name", :attribute, 2, 14, 2, 18]
          assert_includes entries, ["::Hello#greet", :method, 3, 8, 3, 13]

          # Interface, type alias, constant, and global
          assert_includes entries, ["::_Greeter", :interface, 6, 10, 6, 18]
          assert_includes entries, ["::_Greeter#greet", :method, 7, 6, 7, 11]
          assert_includes entries, ["::greeting", :type_alias, 10, 5, 10, 13]
          assert_includes entries, ["::VERSION", :constant, 12, 0, 12, 7]
          assert_includes entries, ["$hello", :global, 14, 0, 14, 6]

          # References to the types written in the file, including the ones declared in other files
          assert_includes entries, ["::String", :reference, 2, 20, 2, 26]
          assert_includes entries, ["::Hello#world", :reference, 3, 14, 3, 19]
          assert_includes entries, ["::String", :reference, 10, 16, 10, 22]
          assert_includes entries, ["::String", :reference, 12, 9, 12, 15]
          assert_includes entries, ["::Hello", :reference, 14, 8, 14, 13]

          # Declarations of other files are not included
          refute entries.any? {|name, kind, *| name == "::String" && kind != :reference }
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

  def test_handle_job_index_signature
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
          reader: worker_reader,
          writer: worker_writer
        )

        {}.tap do |changes|
          changes[Pathname("sig/hello.rbs")] = [Services::ContentChange.string(<<~RBS)]
            class Hello
              def world: () -> Unknown
            end
          RBS
          changes[Pathname("lib/greeter.rb")] = [Services::ContentChange.string(<<~RUBY)]
            class Greeter
              # @rbs (String) -> String
              def greet(name)
                name
              end
            end
          RUBY
          worker.push_buffer { |buffer| buffer.merge!(changes) }
        end

        # An RBS file of the project, without the validation reporting the unknown type
        worker.handle_job(TypeCheckWorker::IndexSignatureJob.new(id: "rbs", path: current_dir + "sig/hello.rbs", target: project.targets[0]))
        master_read_queue.pop.tap do |message|
          assert_equal "rbs", message[:id]
          assert_nil message[:result][:source]
          assert_nil message[:result][:signature][:diagnostics]

          entries = summarize_entries(message[:result][:signature][:entries])
          assert_includes entries, ["::Hello", :class, 0, 6, 0, 11]
          assert_includes entries, ["::Hello#world", :method, 1, 6, 1, 11]
          refute entries.any? {|name, *| name.start_with?("::Greeter") }
        end

        # A Ruby file with inline RBS declarations
        worker.handle_job(TypeCheckWorker::IndexSignatureJob.new(id: "inline", path: current_dir + "lib/greeter.rb", target: project.targets[0]))
        master_read_queue.pop.tap do |message|
          assert_equal "inline", message[:id]
          assert_nil message[:result][:source]
          assert_nil message[:result][:signature][:diagnostics]

          entries = summarize_entries(message[:result][:signature][:entries])
          assert_includes entries, ["::Greeter", :class, 0, 6, 0, 13]
          assert_includes entries, ["::Greeter#greet", :method, 2, 6, 2, 11]
          refute entries.any? {|name, *| name.start_with?("::Hello") }
        end

        # A library RBS file, found by the absolute path
        worker.handle_job(
          TypeCheckWorker::IndexSignatureJob.new(id: "library", path: RBS::EnvironmentLoader::DEFAULT_CORE_ROOT + "string.rbs", target: project.targets[0])
        )
        master_read_queue.pop.tap do |message|
          assert_equal "library", message[:id]
          assert_nil message[:result][:source]
          assert_nil message[:result][:signature][:diagnostics]

          entries = summarize_entries(message[:result][:signature][:entries])
          assert_includes entries.select { _1[0] == "::String" }.map { _1[1] }, :class
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
end
