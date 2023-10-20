require_relative "test_helper"

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

      worker = Server::WorkerProcess.new(reader: nil, writer: nil, stderr: nil, wait_thread: nil, name: "test", index: 0)

      master = Server::Master.new(
        project: project,
        reader: worker_reader,
        writer: worker_writer,
        interaction_worker: nil,
        typecheck_workers: [worker]
      )
      master.instance_variable_set(:@initialize_params, { capabilities: { window: { workDoneProgress: true } } })

      request = TypeCheckRequest.new(guid: "guid")
      request.code_paths << current_dir + "lib/customer.rb"
      request.code_paths << current_dir + "lib/account.rb"
      master.start_type_check(request, last_request: nil, start_progress: true)

      assert_instance_of Server::Master::TypeCheckRequest, master.current_type_check_request

      jobs = flush_queue(master.job_queue)

      assert_any!(jobs) do |job|
        assert_instance_of Master::SendMessageJob, job
        assert_equal :client, job.dest
        assert_equal "window/workDoneProgress/create", job.message[:method]
        assert_equal({ token: request.guid }, job.message[:params])
      end

      assert_any!(jobs) do |job|
        assert_instance_of Master::SendMessageJob, job
        assert_equal :client, job.dest
        assert_equal("$/progress", job.message[:method])
        assert_equal(
          {
            token: request.guid,
            value: { kind: "begin", title: "Type checking", percentage: 0 }
          },
          job.message[:params]
        )
      end

      assert_any!(jobs) do |job|
        assert_instance_of Master::SendMessageJob, job
        assert_equal worker, job.dest
        assert_equal "$/typecheck/start", job.message[:method]

        job.message[:params].tap do |params|
          assert_equal request.guid, params[:guid]
        end
      end
    end
  end

  def test_start_type_check_with_progress_no_support
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

      worker = Server::WorkerProcess.new(reader: nil, writer: nil, stderr: nil, wait_thread: nil, name: "test", index: 0)

      master = Server::Master.new(
        project: project,
        reader: worker_reader,
        writer: worker_writer,
        interaction_worker: nil,
        typecheck_workers: [worker]
      )
      master.instance_variable_set(:@initialize_params, { capabilities: { window: { workDoneProgress: false } } })

      request = TypeCheckRequest.new(guid: "guid")
      request.code_paths << current_dir + "lib/customer.rb"
      request.code_paths << current_dir + "lib/account.rb"
      master.start_type_check(request, last_request: nil, start_progress: true)

      assert_instance_of Server::Master::TypeCheckRequest, master.current_type_check_request

      jobs = flush_queue(master.job_queue)

      assert_none!(jobs) do |job|
        assert_instance_of Master::SendMessageJob, job
        assert_equal :client, job.dest
        assert_equal("window/workDoneProgress/create", job.message[:method])
      end

      assert_any!(jobs) do |job|
        assert_instance_of Master::SendMessageJob, job
        assert_equal :client, job.dest

        assert_equal("$/progress", job.message[:method])
        assert_equal(
          {
            token: request.guid,
            value: { kind: "begin", title: "Type checking", percentage: 0 }
          },
          job.message[:params]
        )
      end

      assert_any!(jobs) do |job|
        assert_instance_of Master::SendMessageJob, job
        assert_equal worker, job.dest

        assert_equal "$/typecheck/start", job.message[:method]

        job.message[:params].tap do |params|
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

      worker = Server::WorkerProcess.new(reader: nil, writer: nil, stderr: nil, wait_thread: nil, name: "test", index: 0)

      master = Server::Master.new(
        project: project,
        reader: worker_reader,
        writer: worker_writer,
        interaction_worker: nil,
        typecheck_workers: [worker]
      )

      request = TypeCheckRequest.new(guid: "guid")
      request.code_paths << current_dir + "lib/customer.rb"
      request.code_paths << current_dir + "lib/account.rb"
      master.start_type_check(request, last_request: nil, start_progress: false)

      assert_nil master.current_type_check_request

      jobs = flush_queue(master.job_queue)

      assert_any!(jobs, size: 1) do |job|
        assert_instance_of Master::SendMessageJob, job
        assert_equal worker, job.dest
        assert_equal "$/typecheck/start", job.message[:method]

        job.message[:params].tap do |params|
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

      worker = Server::WorkerProcess.new(reader: nil, writer: nil, stderr: nil, wait_thread: nil, name: "test", index: 0)

      master = Server::Master.new(
        project: project,
        reader: worker_reader,
        writer: worker_writer,
        interaction_worker: nil,
        typecheck_workers: [worker]
      )

      request = TypeCheckRequest.new(guid: "guid")
      request.code_paths << current_dir + "lib/customer.rb"
      request.code_paths << current_dir + "lib/account.rb"

      master.start_type_check(request, last_request: nil, start_progress: true)

      flush_queue(master.job_queue)

      master.on_type_check_update(guid: "guid", path: current_dir + "lib/customer.rb")

      jobs = flush_queue(master.job_queue)

      assert_equal 1, jobs.size
      jobs[0].tap do |job|
        assert_instance_of Master::SendMessageJob, job
        assert_equal :client, job.dest
        assert_equal "$/progress", job.message[:method]

        job.message[:params].tap do |params|
          assert_equal "guid", params[:token]
          assert_equal "report", params[:value][:kind]
          assert_equal 50, params[:value][:percentage]
        end
      end

      master.on_type_check_update(guid: "guid", path: current_dir + "lib/account.rb")

      jobs = flush_queue(master.job_queue)
      assert_equal 1, jobs.size
      jobs[0].tap do |job|
        assert_instance_of Master::SendMessageJob, job
        assert_equal :client, job.dest
        assert_equal "$/progress", job.message[:method]

        job.message[:params].tap do |params|
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

      worker = Server::WorkerProcess.new(reader: nil, writer: nil, stderr: nil, wait_thread: nil, name: "test", index: 0)

      master = Server::Master.new(
        project: project,
        reader: worker_reader,
        writer: worker_writer,
        interaction_worker: nil,
        typecheck_workers: [worker]
      )

      request = TypeCheckRequest.new(guid: "guid")
      request.code_paths << current_dir + "lib/customer.rb"
      request.code_paths << current_dir + "lib/account.rb"

      master.start_type_check(request, last_request: nil, start_progress: false)

      flush_queue(master.job_queue)

      master.on_type_check_update(guid: "guid", path: current_dir + "lib/customer.rb")
      master.on_type_check_update(guid: "guid", path: current_dir + "lib/account.rb")

      assert_empty master.job_queue
    end
  end

  def test_client_message_initialize_work_done_supported_no
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

      worker = Server::WorkerProcess.new(reader: nil, writer: nil, stderr: nil, wait_thread: nil, name: "test", index: 0)

      master = Server::Master.new(
        project: project,
        reader: worker_reader,
        writer: worker_writer,
        interaction_worker: nil,
        typecheck_workers: [worker]
      )

      master.process_message_from_client(
        {
          method: "initialize",
          params: {
            window: {}
          }
        }
      )

      refute_predicate master, :work_done_progress_supported?
    end
  end

  def test_client_message_initialize_work_done_supported_yes
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

      worker = Server::WorkerProcess.new(reader: nil, writer: nil, stderr: nil, wait_thread: nil, name: "test", index: 0)

      master = Server::Master.new(
        project: project,
        reader: worker_reader,
        writer: worker_writer,
        interaction_worker: nil,
        typecheck_workers: [worker]
      )

      master.process_message_from_client(
        {
          method: "initialize",
          params: {
            capabilities: {
              window: {
                workDoneProgress: true
              }
            }
          }
        }
      )

      assert_predicate master, :work_done_progress_supported?
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

      worker = Server::WorkerProcess.new(reader: nil, writer: nil, stderr: nil, wait_thread: nil, name: "test", index: 0)

      master = Server::Master.new(
        project: project,
        reader: worker_reader,
        writer: worker_writer,
        interaction_worker: nil,
        typecheck_workers: [worker]
      )

      assert_empty master.controller.changed_paths

      master.process_message_from_client(
        {
          method: "textDocument/didChange",
          params: {
            textDocument: {
              uri: "#{file_scheme}#{current_dir + "lib/customer.rb"}"
            }
          }
        }
      )

      jobs = flush_queue(master.job_queue)

      assert_any!(jobs, size: 1) do |job|
        assert_instance_of Master::SendMessageJob, job
        assert_equal worker, job.dest
        assert_equal "textDocument/didChange", job.message[:method]
      end

      assert_operator master.controller.changed_paths, :include?, current_dir + "lib/customer.rb"
    end
  end

  def test_client_message_document_did_save
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

      worker = Server::WorkerProcess.new(reader: nil, writer: nil, stderr: nil, wait_thread: nil, name: "test", index: 0)

      master = Server::Master.new(
        project: project,
        reader: worker_reader,
        writer: worker_writer,
        interaction_worker: nil,
        typecheck_workers: [worker]
      )

      assert_empty master.controller.changed_paths

      master.process_message_from_client(
        {
          method: "textDocument/didSave",
          params: {
            textDocument: {
              uri: "#{file_scheme}#{current_dir + "lib/customer.rb"}"
            }
          }
        }
      )

      jobs = flush_queue(master.job_queue)
      assert_empty jobs
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

      worker = Server::WorkerProcess.new(reader: nil, writer: nil, stderr: nil, wait_thread: nil, name: "test", index: 0)

      master = Server::Master.new(
        project: project,
        reader: worker_reader,
        writer: worker_writer,
        interaction_worker: nil,
        typecheck_workers: [worker]
      )

      assert_empty master.controller.priority_paths

      master.process_message_from_client(
        {
          method: "textDocument/didOpen",
          params: {
            textDocument: {
              uri: "#{file_scheme}#{current_dir + "lib/customer.rb"}"
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
              uri: "#{file_scheme}#{current_dir + "lib/customer.rb"}"
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

      interaction_worker = Server::WorkerProcess.start_worker(:interaction, name: "interaction", steepfile: steepfile, steep_command: nil)
      typecheck_workers = Server::WorkerProcess.start_typecheck_workers(steepfile: steepfile, count: 1, args: [], steep_command: nil)

      master = Server::Master.new(
        project: project,
        reader: worker_reader,
        writer: worker_writer,
        interaction_worker: interaction_worker,
        typecheck_workers: typecheck_workers
      )

      main_thread = Thread.new do
        Thread.current.abort_on_exception = true
        master.start()
      end

      ui = LSPDouble.new(reader: master_reader, writer: master_writer)
      ui.start do
        ui.open_file(project.absolute_path(Pathname("lib/foo.rb")))
        ui.edit_file(project.absolute_path(Pathname("lib/foo.rb")), content: <<-RUBY, version: 0)
class Foo
end
        RUBY
        ui.save_file(project.absolute_path(Pathname("lib/foo.rb")))

        ui.open_file(project.absolute_path(Pathname("lib/bar.rb")))
        ui.edit_file(project.absolute_path(Pathname("lib/bar.rb")), content: <<-RUBY, version: 0)
class Bar
end
        RUBY
        ui.save_file(project.absolute_path(Pathname("lib/bar.rb")))

        finally_holds do
          assert_equal(
            [
              {
                range: {
                  start: { line: 0, character: 6 },
                  end: { line: 0, character: 9 }
                },
                severity: 2,
                code: "Ruby::UnknownConstant",
                message: "Cannot find the declaration of class: `Foo`"
              }
            ],
            ui.diagnostics_for(project.absolute_path(Pathname("lib/foo.rb")))
          )
          assert_equal(
            [
              {
                range: {
                  start: { line: 0, character: 6 },
                  end: { line: 0, character: 9 }
                },
                severity: 2,
                code: "Ruby::UnknownConstant",
                message: "Cannot find the declaration of class: `Bar`"
              }
            ],
            ui.diagnostics_for(project.absolute_path(Pathname("lib/bar.rb")))
          )
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
end
      EOF

      project = Project.new(steepfile_path: steepfile)
      Project::DSL.parse(project, steepfile.read)

      interaction_worker = Server::WorkerProcess.start_worker(:interaction, name: "interaction", steepfile: steepfile, steep_command: nil)
      typecheck_workers = Server::WorkerProcess.start_typecheck_workers(steepfile: steepfile, count: 1, args: [], steep_command: nil)

      master = Server::Master.new(project: project,
                                  reader: worker_reader,
                                  writer: worker_writer,
                                  interaction_worker: interaction_worker,
                                  typecheck_workers: typecheck_workers)

      main_thread = Thread.new do
        Thread.current.abort_on_exception = true
        master.start()
      end

      ui = LSPDouble.new(reader: master_reader, writer: master_writer)
      ui.start do
        ui.open_file(project.absolute_path(Pathname("lib/foo.rb")))
        ui.edit_file(project.absolute_path(Pathname("lib/foo.rb")), content: <<-RUBY, version: 0)
class Foo
end
        RUBY
        ui.save_file(project.absolute_path(Pathname("lib/foo.rb")))

        finally_holds do
          assert_equal(
            [
              {
                range: {
                  start: { line: 0, character: 6 },
                  end: { line: 0, character: 9 }
                },
                severity: 2,
                code: "Ruby::UnknownConstant",
                message: "Cannot find the declaration of class: `Foo`"
              }
            ],
            ui.diagnostics_for(project.absolute_path(Pathname("lib/foo.rb")))
          )
        end

        ui.open_file(project.absolute_path(Pathname("sig/foo.rbs")))
        ui.edit_file(project.absolute_path(Pathname("sig/foo.rbs")), content: <<-RBS, version: 0)
class Foo
  def foo: () -> void
end
        RBS
        ui.save_file(project.absolute_path(Pathname("sig/foo.rbs")))

        finally_holds do
          assert_equal 1, ui.diagnostics_for(project.absolute_path(Pathname("lib/foo.rb"))).size
        end

        finally_holds timeout: 30 do
          assert_empty ui.diagnostics_for(project.absolute_path(Pathname("sig/foo.rbs")))
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
end
      EOF

      project = Project.new(steepfile_path: steepfile)
      Project::DSL.parse(project, steepfile.read)

      interaction_worker = Server::WorkerProcess.start_worker(:interaction, name: "interaction", steepfile: steepfile, steep_command: nil)
      typecheck_workers = Server::WorkerProcess.start_typecheck_workers(steepfile: steepfile, count: 2, args: [], steep_command: nil)

      master = Server::Master.new(project: project,
                                  reader: worker_reader,
                                  writer: worker_writer,
                                  interaction_worker: interaction_worker,
                                  typecheck_workers: typecheck_workers)

      main_thread = Thread.new do
        Thread.current.abort_on_exception = true
        master.start()
      end

      ui = LSPDouble.new(reader: master_reader, writer: master_writer)
      ui.start do
        ui.open_file(project.absolute_path(Pathname("lib/foo.rb")))
        ui.edit_file(project.absolute_path(Pathname("lib/foo.rb")), content: <<-RUBY, version: 0)
x = 100
x.ab
        RUBY

        hover = ui.hover_on(path: project.absolute_path(Pathname("lib/foo.rb")), line: 1, character: 0)

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
end
      EOF

      project = Project.new(steepfile_path: steepfile)
      Project::DSL.parse(project, steepfile.read)

      interaction_worker = Server::WorkerProcess.start_worker(:interaction, name: "interaction", steepfile: steepfile, steep_command: nil)
      typecheck_workers = Server::WorkerProcess.start_typecheck_workers(steepfile: steepfile, count: 2, args: [], steep_command: nil)

      master = Server::Master.new(project: project,
                                  reader: worker_reader,
                                  writer: worker_writer,
                                  interaction_worker: interaction_worker,
                                  typecheck_workers: typecheck_workers)

      main_thread = Thread.new do
        Thread.current.abort_on_exception = true
        master.start()
      end

      ui = LSPDouble.new(reader: master_reader, writer: master_writer)
      ui.start do
        ui.open_file(project.absolute_path(Pathname("sig/foo.rbs")))
        ui.edit_file(project.absolute_path(Pathname("sig/foo.rbs")), content: <<-RUBY, version: 0)
class FooClassNew
end
        RUBY
        ui.save_file(project.absolute_path(Pathname("sig/foo.rbs")))

        finally_holds do
          ui.workspace_symbol().tap do |symbols|
            assert symbols.find { |symbol| symbol[:name] == "FooClassNew" }
          end
        end

        finally_holds do
          ui.workspace_symbol("array").tap do |symbols|
            assert symbols.find { |symbol| symbol[:name] == "Array" }
          end
        end
      end

      main_thread.join
    end
  end

  def test_untitled_file_notifications
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

      worker = Server::WorkerProcess.new(reader: nil, writer: nil, stderr: nil, wait_thread: nil, name: "test", index: 0)

      master = Server::Master.new(
        project: project,
        reader: worker_reader,
        writer: worker_writer,
        interaction_worker: Object.new,
        typecheck_workers: [worker]
      )

      assert_empty master.controller.changed_paths

      master.process_message_from_client(
        {
          method: "textDocument/didOpen",
          params: {
            textDocument: {
              uri: "untitled:Untitled-1"
            }
          }
        }
      )

      master.process_message_from_client(
        {
          method: "textDocument/didChange",
          params: {
            textDocument: {
              uri: "untitled:Untitled-1"
            }
          }
        }
      )

      master.process_message_from_client(
        {
          method: "textDocument/didSave",
          params: {
            textDocument: {
              uri: "untitled:Untitled-1"
            }
          }
        }
      )

      master.process_message_from_client(
        {
          method: "textDocument/didClose",
          params: {
            textDocument: {
              uri: "untitled:Untitled-1"
            }
          }
        }
      )

      jobs = flush_queue(master.job_queue)
      assert_empty jobs

      master.process_message_from_client(
        {
          method: "textDocument/hover",
          id: "hover_id",
          params: {
            textDocument: {
              uri: "untitled:Untitled-1"
            }
          }
        }
      )

      assert_equal(
        [Master::SendMessageJob.to_client(message: { id: "hover_id", result: nil })],
        flush_queue(master.job_queue)
      )

      master.process_message_from_client(
        {
          method: "textDocument/completion",
          id: "completion_id",
          params: {
            textDocument: {
              uri: "untitled:Untitled-1"
            }
          }
        }
      )

      assert_equal(
        [Master::SendMessageJob.to_client(message: { id: "completion_id", result: nil })],
        flush_queue(master.job_queue)
      )

      master.process_message_from_client(
        {
          method: "textDocument/definition",
          id: "definition_id",
          params: {
            textDocument: {
              uri: "untitled:Untitled-1"
            }
          }
        }
      )

      assert_equal(
        [Master::SendMessageJob.to_client(message: { id: "definition_id", result: [] })],
        flush_queue(master.job_queue)
      )

      master.process_message_from_client(
        {
          method: "textDocument/implementation",
          id: "implementation_id",
          params: {
            textDocument: {
              uri: "untitled:Untitled-1"
            }
          }
        }
      )

      assert_equal(
        [Master::SendMessageJob.to_client(message: { id: "implementation_id", result: [] })],
        flush_queue(master.job_queue)
      )
    end
  end
end
