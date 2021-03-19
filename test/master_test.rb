require "test_helper"

class MasterTest < Minitest::Test
  include TestHelper
  include ShellHelper
  include LSPTestHelper

  include Steep

  Master = Server::Master
  TypeCheckController = Master::TypeCheckController
  TypeCheckRequest = Master::TypeCheckRequest

  def dirs
    @dirs ||= []
  end

  def test_start_type_check_with_progress
    in_tmpdir do
      steepfile = current_dir + "Steepfile"
      steepfile.write(<<-EOF)
target :lib do
  check "lib"
  signature "sig"
end
      EOF

      project = Project.new(steepfile_path: steepfile)
      Project::DSL.parse(project, steepfile.read)

      write_queue = []
      worker = []

      master = Server::Master.new(
        project: project,
        reader: worker_reader,
        writer: worker_writer,
        interaction_worker: nil,
        typecheck_workers: [worker],
        queue: write_queue
      )

      request = TypeCheckRequest.new(guid: "guid")
      request.code_paths << current_dir + "lib/customer.rb"
      request.code_paths << current_dir + "lib/account.rb"
      master.start_type_check(request, last_request: nil, start_progress: true)

      assert_instance_of Server::Master::TypeCheckRequest, master.current_type_check_request

      assert_any!(write_queue) do |message|
        assert_equal("window/workDoneProgress/create", message[:method])
        assert_equal({ token: request.guid }, message[:params])
      end

      assert_any!(write_queue) do |message|
        assert_equal("$/progress", message[:method])
        assert_equal(
          {
            token: request.guid,
            value: { kind: "begin", title: "Type checking", percentage: 0 }
          },
          message[:params]
        )
      end

      assert_equal 1, worker.size
      worker[0].tap do |message|
        assert_equal "$/typecheck/start", message[:method]

        message[:params].tap do |params|
          assert_equal request.guid, params[:guid]
        end
      end
    end
  end

  def test_start_type_check_without_progress
    in_tmpdir do
      steepfile = current_dir + "Steepfile"
      steepfile.write(<<-EOF)
target :lib do
  check "lib"
  signature "sig"
end
      EOF

      project = Project.new(steepfile_path: steepfile)
      Project::DSL.parse(project, steepfile.read)

      write_queue = []
      worker = []

      master = Server::Master.new(
        project: project,
        reader: worker_reader,
        writer: worker_writer,
        interaction_worker: nil,
        typecheck_workers: [worker],
        queue: write_queue
      )

      request = TypeCheckRequest.new(guid: "guid")
      request.code_paths << current_dir + "lib/customer.rb"
      request.code_paths << current_dir + "lib/account.rb"
      master.start_type_check(request, last_request: nil, start_progress: false)

      assert_nil master.current_type_check_request

      assert_empty write_queue

      assert_equal 1, worker.size
      worker[0].tap do |message|
        assert_equal "$/typecheck/start", message[:method]

        message[:params].tap do |params|
          assert_equal request.guid, params[:guid]
        end
      end
    end
  end

  def test_on_type_check_update_with_progress
    in_tmpdir do
      steepfile = current_dir + "Steepfile"
      steepfile.write(<<-EOF)
target :lib do
  check "lib"
  signature "sig"
end
      EOF

      project = Project.new(steepfile_path: steepfile)
      Project::DSL.parse(project, steepfile.read)

      write_queue = []
      worker = []

      master = Server::Master.new(
        project: project,
        reader: worker_reader,
        writer: worker_writer,
        interaction_worker: nil,
        typecheck_workers: [worker],
        queue: write_queue
      )

      request = TypeCheckRequest.new(guid: "guid")
      request.code_paths << current_dir + "lib/customer.rb"
      request.code_paths << current_dir + "lib/account.rb"

      master.start_type_check(request, last_request: nil, start_progress: true)

      write_queue.clear()

      master.on_type_check_update(guid: "guid", path: current_dir + "lib/customer.rb")

      assert_equal 1, write_queue.size
      write_queue[0].tap do |message|
        assert_equal "$/progress", message[:method]

        message[:params].tap do |params|
          assert_equal "guid", params[:token]
          assert_equal "report", params[:value][:kind]
          assert_equal 50, params[:value][:percentage]
        end
      end

      write_queue.clear()

      master.on_type_check_update(guid: "guid", path: current_dir + "lib/account.rb")

      assert_equal 1, write_queue.size
      write_queue[0].tap do |message|
        assert_equal "$/progress", message[:method]

        message[:params].tap do |params|
          assert_equal "guid", params[:token]
          assert_equal "end", params[:value][:kind]
        end
      end

      assert_nil master.current_type_check_request
    end
  end

  def test_on_type_check_update_without_progress
    in_tmpdir do
      steepfile = current_dir + "Steepfile"
      steepfile.write(<<-EOF)
target :lib do
  check "lib"
  signature "sig"
end
      EOF

      project = Project.new(steepfile_path: steepfile)
      Project::DSL.parse(project, steepfile.read)

      write_queue = []
      worker = []

      master = Server::Master.new(
        project: project,
        reader: worker_reader,
        writer: worker_writer,
        interaction_worker: nil,
        typecheck_workers: [worker],
        queue: write_queue
      )

      request = TypeCheckRequest.new(guid: "guid")
      request.code_paths << current_dir + "lib/customer.rb"
      request.code_paths << current_dir + "lib/account.rb"

      master.start_type_check(request, last_request: nil, start_progress: false)

      write_queue.clear()

      master.on_type_check_update(guid: "guid", path: current_dir + "lib/customer.rb")
      master.on_type_check_update(guid: "guid", path: current_dir + "lib/account.rb")

      assert_empty write_queue
    end
  end

  def test_client_message_document_did_change
    in_tmpdir do
      steepfile = current_dir + "Steepfile"
      steepfile.write(<<-EOF)
target :lib do
  check "lib"
  signature "sig"
end
      EOF

      project = Project.new(steepfile_path: steepfile)
      Project::DSL.parse(project, steepfile.read)

      write_queue = []
      worker = []

      master = Server::Master.new(
        project: project,
        reader: worker_reader,
        writer: worker_writer,
        interaction_worker: nil,
        typecheck_workers: [worker],
        queue: write_queue
      )

      assert_empty master.controller.changed_paths

      master.process_message_from_client(
        {
          method: "textDocument/didChange",
          params: {
            textDocument: {
              uri: "file://#{current_dir + "lib/customer.rb"}"
            }
          }
        }
      )

      assert_operator master.controller.changed_paths, :include?, current_dir + "lib/customer.rb"
    end
  end

  def test_client_message_document_did_open_close
    in_tmpdir do
      steepfile = current_dir + "Steepfile"
      steepfile.write(<<-EOF)
target :lib do
  check "lib"
  signature "sig"
end
      EOF

      project = Project.new(steepfile_path: steepfile)
      Project::DSL.parse(project, steepfile.read)

      write_queue = []
      worker = []

      master = Server::Master.new(
        project: project,
        reader: worker_reader,
        writer: worker_writer,
        interaction_worker: nil,
        typecheck_workers: [worker],
        queue: write_queue
      )

      assert_empty master.controller.priority_paths

      master.process_message_from_client(
        {
          method: "textDocument/didOpen",
          params: {
            textDocument: {
              uri: "file://#{current_dir + "lib/customer.rb"}"
            }
          }
        }
      )

      assert_operator master.controller.priority_paths, :include?, current_dir + "lib/customer.rb"

      master.process_message_from_client(
        {
          method: "textDocument/didClose",
          params: {
            textDocument: {
              uri: "file://#{current_dir + "lib/customer.rb"}"
            }
          }
        }
      )

      refute_operator master.controller.priority_paths, :include?, current_dir + "lib/customer.rb"
    end
  end

  def test_code_type_check
    in_tmpdir do
      steepfile = current_dir + "Steepfile"
      steepfile.write(<<-EOF)
target :lib do
  check "lib"
  signature "sig"
end
EOF

      project = Project.new(steepfile_path: steepfile)
      Project::DSL.parse(project, steepfile.read)

      interaction_worker = Server::WorkerProcess.spawn_worker(:interaction, name: "interaction", steepfile: steepfile)
      typecheck_workers = Server::WorkerProcess.spawn_typecheck_workers(steepfile: steepfile, count: 1, args: [])

      master = Server::Master.new(project: project,
                                  reader: worker_reader,
                                  writer: worker_writer,
                                  interaction_worker: interaction_worker,
                                  typecheck_workers: typecheck_workers)

      main_thread = Thread.new do
        master.start()
      end
      main_thread.abort_on_exception = true

      ui = LSPDouble.new(reader: master_reader, writer: master_writer)
      ui.start do
        ui.open_file(project.absolute_path(Pathname("lib/foo.rb")))
        ui.edit_file(project.absolute_path(Pathname("lib/foo.rb")), content: <<-RUBY, version: 0)
class Foo
end
        RUBY

        ui.open_file(project.absolute_path(Pathname("lib/bar.rb")))
        ui.edit_file(project.absolute_path(Pathname("lib/bar.rb")), content: <<-RUBY, version: 0)
class Bar
end
        RUBY

        finally_holds do
          assert_equal [], ui.diagnostics_for(project.absolute_path(Pathname("lib/foo.rb")))
          assert_equal [], ui.diagnostics_for(project.absolute_path(Pathname("lib/bar.rb")))
        end
      end

      main_thread.join
    end
  end

  def test_signature_type_check
    in_tmpdir do
      steepfile = current_dir + "Steepfile"
      steepfile.write(<<-EOF)
target :lib do
  check "lib"
  signature "sig"
  typing_options :strict
end
      EOF

      project = Project.new(steepfile_path: steepfile)
      Project::DSL.parse(project, steepfile.read)

      interaction_worker = Server::WorkerProcess.spawn_worker(:interaction, name: "interaction", steepfile: steepfile)
      typecheck_workers = Server::WorkerProcess.spawn_typecheck_workers(steepfile: steepfile, count: 1, args: [])

      master = Server::Master.new(project: project,
                                  reader: worker_reader,
                                  writer: worker_writer,
                                  interaction_worker: interaction_worker,
                                  typecheck_workers: typecheck_workers)

      main_thread = Thread.new do
        master.start()
      end
      main_thread.abort_on_exception = true

      ui = LSPDouble.new(reader: master_reader, writer: master_writer)
      ui.start do
        ui.open_file(project.absolute_path(Pathname("lib/foo.rb")))
        ui.edit_file(project.absolute_path(Pathname("lib/foo.rb")), content: <<-RUBY, version: 0)
class Foo
end
        RUBY

        finally_holds do
          assert_equal [],
                       ui.diagnostics_for(project.absolute_path(Pathname("lib/foo.rb")))
        end

        ui.open_file(project.absolute_path(Pathname("sig/foo.rbs")))
        ui.edit_file(project.absolute_path(Pathname("sig/foo.rbs")), content: <<-RBS, version: 0)
class Foo
  def foo: () -> void
end
        RBS


        finally_holds do
          assert_equal 1, ui.diagnostics_for(project.absolute_path(Pathname("lib/foo.rb"))).size
        end

        finally_holds timeout: 30 do
          assert_equal [], ui.diagnostics_for(project.absolute_path(Pathname("sig/foo.rbs")))
        end
      end

      main_thread.join
    end
  end

  def test_code_interaction
    in_tmpdir do
      steepfile = current_dir + "Steepfile"
      steepfile.write(<<-EOF)
target :lib do
  check "lib"
  signature "sig"
  typing_options :strict
end
      EOF

      project = Project.new(steepfile_path: steepfile)
      Project::DSL.parse(project, steepfile.read)

      interaction_worker = Server::WorkerProcess.spawn_worker(:interaction, name: "interaction", steepfile: steepfile)
      typecheck_workers = Server::WorkerProcess.spawn_typecheck_workers(steepfile: steepfile, count: 2, args: [])

      master = Server::Master.new(project: project,
                                  reader: worker_reader,
                                  writer: worker_writer,
                                  interaction_worker: interaction_worker,
                                  typecheck_workers: typecheck_workers)

      main_thread = Thread.new do
        master.start()
      end
      main_thread.abort_on_exception = true

      ui = LSPDouble.new(reader: master_reader, writer: master_writer)
      ui.start do
        ui.open_file(project.absolute_path(Pathname("lib/foo.rb")))
        ui.edit_file(project.absolute_path(Pathname("lib/foo.rb")), content: <<-RUBY, version: 0)
x = 100
x.ab
        RUBY

        hover = ui.hover_on(path: project.absolute_path(Pathname("lib/foo.rb")), line: 1, character: 0)

        assert_equal({ kind: "markdown", value: "`x`: `::Integer`" }, hover[:contents])
        assert_equal({ line: 1, character: 0 }, hover[:range][:start])
        assert_equal({ line: 1, character: 1 }, hover[:range][:end])

        completion = ui.complete_on(path: project.absolute_path(Pathname("lib/foo.rb")), line: 1, character: 4)

        assert_instance_of Array, completion[:items]
      end

      main_thread.join
    end
  end

  def test_workspace_symbol
    in_tmpdir do
      steepfile = current_dir + "Steepfile"
      steepfile.write(<<-EOF)
target :lib do
  check "lib"
  signature "sig"
  typing_options :strict
end
      EOF

      project = Project.new(steepfile_path: steepfile)
      Project::DSL.parse(project, steepfile.read)

      interaction_worker = Server::WorkerProcess.spawn_worker(:interaction, name: "interaction", steepfile: steepfile)
      typecheck_workers = Server::WorkerProcess.spawn_typecheck_workers(steepfile: steepfile, count: 2, args: [])

      master = Server::Master.new(project: project,
                                  reader: worker_reader,
                                  writer: worker_writer,
                                  interaction_worker: interaction_worker,
                                  typecheck_workers: typecheck_workers)

      main_thread = Thread.new do
        master.start()
      end
      main_thread.abort_on_exception = true

      ui = LSPDouble.new(reader: master_reader, writer: master_writer)
      ui.start do
        ui.open_file(project.absolute_path(Pathname("sig/foo.rbs")))
        ui.edit_file(project.absolute_path(Pathname("sig/foo.rbs")), content: <<-RUBY, version: 0)
class FooClassNew
end
        RUBY

        ui.workspace_symbol().tap do |symbols|
          assert symbols.find {|symbol| symbol[:name] == "FooClassNew" }
        end

        ui.workspace_symbol("array").tap do |symbols|
          assert symbols.find {|symbol| symbol[:name] == "Array" }
        end
      end

      main_thread.join
    end
  end
end
