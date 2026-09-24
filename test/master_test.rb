require_relative "test_helper"

# @rbs use Steep::*

class MasterTest < Minitest::Test
  include TestHelper
  include ShellHelper
  include LSPTestHelper

  include Steep

  # @rbs skip
  Master = Server::Master
  # @rbs skip
  TypeCheckController = Server::TypeCheckController
  # @rbs skip
  WorkDoneProgress = Server::WorkDoneProgress

  # @rbs!
  #   class Master = Server::Master
  #   class TypeCheckController = Server::TypeCheckController
  #   class WorkDoneProgress = Server::WorkDoneProgress

  DEFAULT_CLI_LSP_INITIALIZE_PARAMS = Drivers::Utils::DriverHelper::DEFAULT_CLI_LSP_INITIALIZE_PARAMS

  include Server::CustomMethods

  def dirs
    @dirs ||= []
  end

  def test_start_workers_on_initialize
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
      launcher = WorkersLauncher.new(worker)

      master = Server::Master.new(
        project: project,
        reader: worker_reader,
        writer: worker_writer,
        launcher: launcher
      )

      # The master reaches the workers through the launcher
      assert_equal [worker], master.typecheck_workers
      assert_nil launcher.started_service

      # The launcher starts the workers with the environments the project is loaded into
      master.process_message_from_client({ id: "initialize", method: "initialize", params: DEFAULT_CLI_LSP_INITIALIZE_PARAMS })
      flush_queue(master.write_queue)

      assert_same master.controller.type_check_service, launcher.started_service
    end
  end

  def test_kill_stops_launcher
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

      launcher = WorkersLauncher.new

      master = Server::Master.new(
        project: project,
        reader: worker_reader,
        writer: worker_writer,
        launcher: launcher
      )

      refute launcher.stopped?
      master.kill
      assert launcher.stopped?
    end
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
        launcher: WorkersLauncher.new(worker)
      )
      master.assign_initialize_params(DEFAULT_CLI_LSP_INITIALIZE_PARAMS.merge(capabilities: { window: { workDoneProgress: true } }))

      master.controller.add_dirty_code_path current_dir + "lib/customer.rb"
      master.controller.add_dirty_code_path current_dir + "lib/account.rb"

      progress = master.work_done_progress("guid")
      master.start_type_check(last_request: nil, progress: progress, report_progress_threshold: 0, needs_response: true)

      assert_instance_of Server::TypeCheckController::Request, master.current_type_check_request

      jobs = flush_queue(master.write_queue)

      assert_any!(jobs) do |job|
        assert_instance_of Master::SendMessageJob, job
        assert_equal :client, job.dest
        assert_equal "window/workDoneProgress/create", job.message[:method]
        assert_equal({ token: "guid" }, job.message[:params])
      end

      assert_any!(jobs) do |job|
        assert_instance_of Master::SendMessageJob, job
        assert_equal :client, job.dest
        assert_equal("$/progress", job.message[:method])
        assert_equal(
          {
            token: "guid",
            value: { kind: "begin", title: "Type checking", percentage: 0, cancellable: false }
          },
          job.message[:params]
        )
      end

      assert_any!(jobs) do |job|
        assert_instance_of Master::SendMessageJob, job
        assert_equal worker, job.dest
        assert_equal TypeCheck__File::METHOD, job.message[:method]
        assert_equal "guid", job.message[:params][:guid]
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
        launcher: WorkersLauncher.new(worker)
      )
      master.assign_initialize_params(DEFAULT_CLI_LSP_INITIALIZE_PARAMS)

      master.controller.add_dirty_code_path current_dir + "lib/customer.rb"
      master.controller.add_dirty_code_path current_dir + "lib/account.rb"

      progress = master.work_done_progress("guid")
      master.start_type_check(last_request: nil, progress: progress, report_progress_threshold: 0, needs_response: true)

      assert_instance_of Server::TypeCheckController::Request, master.current_type_check_request

      jobs = flush_queue(master.write_queue)

      assert_none!(jobs) do |job|
        assert_instance_of Master::SendMessageJob, job
        assert_equal :client, job.dest
        assert_equal("window/workDoneProgress/create", job.message[:method])
      end

      assert_any!(jobs) do |job|
        assert_instance_of Master::SendMessageJob, job
        assert_equal worker, job.dest

        assert_equal TypeCheck__File::METHOD, job.message[:method]
        assert_equal "guid", job.message[:params][:guid]
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
        launcher: WorkersLauncher.new(worker)
      )
      master.assign_initialize_params(DEFAULT_CLI_LSP_INITIALIZE_PARAMS)

      master.controller.add_dirty_code_path current_dir + "lib/customer.rb"
      master.controller.add_dirty_code_path current_dir + "lib/account.rb"

      progress = master.work_done_progress("guid")
      master.start_type_check(last_request: nil, progress: progress, report_progress_threshold: 10, needs_response: true)

      refute_nil master.current_type_check_request

      # One request per file, and nothing else without progress
      jobs = flush_queue(master.write_queue)

      assert_equal 2, jobs.size
      jobs.each do |job|
        assert_instance_of Master::SendMessageJob, job
        assert_equal worker, job.dest
        assert_equal TypeCheck__File::METHOD, job.message[:method]
        assert_equal "guid", job.message[:params][:guid]
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
        launcher: WorkersLauncher.new(worker)
      )
      master.assign_initialize_params(DEFAULT_CLI_LSP_INITIALIZE_PARAMS.merge(capabilities: { window: { workDoneProgress: true } }))

      master.controller.add_dirty_code_path current_dir + "lib/customer.rb"
      master.controller.add_dirty_code_path current_dir + "lib/account.rb"

      progress = master.work_done_progress("guid")
      master.start_type_check(last_request: nil, progress: progress, report_progress_threshold: 0, needs_response: true)

      flush_queue(master.write_queue)

      master.on_type_check_update(guid: "guid", path: current_dir + "lib/customer.rb", target: project.targets[0], source: { diagnostics: nil, entries: nil })

      jobs = flush_queue(master.write_queue)

      assert_equal 1, jobs.size

      assert_any!(jobs) do |job|
        assert_instance_of Master::SendMessageJob, job
        assert_equal :client, job.dest
        assert_equal "$/progress", job.message[:method]

        job.message[:params].tap do |params|
          assert_equal "guid", params[:token]
          assert_equal "report", params[:value][:kind]
          assert_equal 50, params[:value][:percentage]
        end
      end

      master.on_type_check_update(guid: "guid", path: current_dir + "lib/account.rb", target: project.targets[0], source: { diagnostics: [], entries: [] })

      jobs = flush_queue(master.write_queue)

      assert_equal 4, jobs.size
      assert_any!(jobs) do |job|
        assert_instance_of Master::SendMessageJob, job
        assert_equal :client, job.dest
        assert_equal "$/progress", job.message[:method]

        job.message[:params].tap do |params|
          assert_equal "guid", params[:token]
          assert_equal "report", params[:value][:kind]
          assert_equal 100, params[:value][:percentage]
        end
      end
      assert_any!(jobs) do |job|
        assert_instance_of Master::SendMessageJob, job
        assert_equal :client, job.dest
        assert_equal "$/progress", job.message[:method]

        job.message[:params].tap do |params|
          assert_equal "guid", params[:token]
          assert_equal "end", params[:value][:kind]
        end
      end
      assert_any!(jobs) do |job|
        # Response to $/steep/typecheck request
        assert_instance_of Master::SendMessageJob, job
        assert_equal :client, job.dest
        assert_equal "guid", job.message[:id]
      end

      assert_nil master.current_type_check_request
    end
  end

  def test_on_type_check_update_stores_results_in_database
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
        launcher: WorkersLauncher.new(worker)
      )
      master.assign_initialize_params(DEFAULT_CLI_LSP_INITIALIZE_PARAMS.merge(capabilities: { window: { workDoneProgress: true } }))

      master.controller.add_dirty_code_path current_dir + "lib/customer.rb"

      progress = master.work_done_progress("guid")
      master.start_type_check(last_request: nil, progress: progress, report_progress_threshold: 0, needs_response: true)

      flush_queue(master.write_queue)

      master.on_type_check_update(
        guid: "guid",
        path: current_dir + "lib/customer.rb",
        target: project.targets[0],
        source: {
          diagnostics: [],
          entries: [
            ["::Customer", 0, 0, 6, 0, 14],
            ["::Customer#name", 0, 1, 6, 1, 10]
          ]
        },
        signature: {
          diagnostics: [],
          entries: [
            ["::Customer#name", 0, 1, 6, 1, 10]
          ]
        }
      )

      database = master.type_check_database

      assert_equal [], database.diagnostics(current_dir + "lib/customer.rb")

      # The Ruby code and the inline declarations are stored in both tables
      definitions = database.definitions("::Customer#name")
      assert_equal [current_dir + "lib/customer.rb"], definitions.map(&:path).uniq
      assert_equal [[:ruby, 1], [:rbs, 1]], definitions.map { [_1.source, _1.start_line] }

      # Results of unknown guids are not stored
      master.on_type_check_update(
        guid: "different-guid",
        path: current_dir + "lib/customer.rb",
        target: project.targets[0],
        source: { diagnostics: nil, entries: [["::Other", 0, 0, 0, 0, 5]] }
      )
      assert_equal [], database.definitions("::Other")
    end
  end

  def test_hover_via_typecheck_worker
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
        launcher: WorkersLauncher.new(worker)
      )
      master.assign_initialize_params(DEFAULT_CLI_LSP_INITIALIZE_PARAMS)
      master.controller.load(command_line_args: [])

      master.process_message_from_client(
        {
          method: "textDocument/hover",
          id: "hover_id",
          params: {
            textDocument: { uri: "#{file_scheme}#{current_dir}/lib/foo.rb" },
            position: { line: 3, character: 9 }
          }
        }
      )

      # The request is forwarded to the typecheck worker as `$/steep/hover`
      jobs = flush_queue(master.write_queue)
      request = jobs.find { |job| job.message[:method] == Hover::METHOD } or raise
      assert_equal worker, request.dest
      assert_equal(
        { uri: "#{file_scheme}#{current_dir}/lib/foo.rb", position: { line: 3, character: 9 } },
        request.message[:params]
      )
      assert_equal 1, master.interaction_jobs_in_flight[worker]

      # The result is rendered with the environment of the master, on the main thread
      master.result_controller.process_response(
        {
          id: request.message[:id],
          result: {
            target: "lib",
            range: { start: { line: 3, character: 8 }, end: { line: 3, character: 10 } },
            content: { kind: "variable", name: "xs", type: "::Array[::Integer]" }
          }
        }
      )
      assert_equal 0, master.interaction_jobs_in_flight[worker]

      jobs = flush_queue(master.write_queue)
      assert_equal 1, jobs.size
      jobs[0].tap do |job|
        assert_equal :client, job.dest
        assert_equal "hover_id", job.message[:id]

        hover = job.message[:result]
        assert_instance_of LSP::Interface::Hover, hover
        assert_equal({ start: { line: 3, character: 8 }, end: { line: 3, character: 10 } }.to_json, hover.range.to_json)
        assert_equal "**Local variable** `xs: ::Array[::Integer]`\n", hover.contents.value
      end

      # Nothing at the position
      master.process_message_from_client(
        {
          method: "textDocument/hover",
          id: "hover_id2",
          params: {
            textDocument: { uri: "#{file_scheme}#{current_dir}/lib/foo.rb" },
            position: { line: 0, character: 0 }
          }
        }
      )
      request = flush_queue(master.write_queue).find { |job| job.message[:method] == Hover::METHOD } or raise
      master.result_controller.process_response({ id: request.message[:id], result: nil })

      assert_equal(
        [Master::SendMessageJob.to_client(message: { id: "hover_id2", result: nil })],
        flush_queue(master.write_queue)
      )
    end
  end

  def test_signature_help_via_typecheck_worker
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
        launcher: WorkersLauncher.new(worker)
      )
      master.assign_initialize_params(DEFAULT_CLI_LSP_INITIALIZE_PARAMS)
      master.controller.load(command_line_args: [])

      request_signature_help = -> (id, context = nil) do
        params = {
          textDocument: { uri: "#{file_scheme}#{current_dir}/lib/foo.rb" },
          position: { line: 3, character: 9 }
        }
        params[:context] = context if context

        master.process_message_from_client({ method: "textDocument/signatureHelp", id: id, params: params })
        flush_queue(master.write_queue).find { |job| job.message[:method] == SignatureHelp::METHOD } or raise
      end

      # A signature help is rendered on the main thread
      request = request_signature_help["help1"]
      master.result_controller.process_response(
        {
          id: request.message[:id],
          result: {
            signature_help: {
              target: "lib",
              signatures: [{ method_type: "(::String) -> void", parameters: ["::String"], active_parameter: 0, method: nil }],
              active_signature: 0
            },
            syntax_error: false
          }
        }
      )

      jobs = flush_queue(master.write_queue)
      assert_equal 1, jobs.size
      help = jobs[0].message[:result]
      assert_instance_of LSP::Interface::SignatureHelp, help
      assert_equal ["(::String) -> void"], help.signatures.map(&:label)

      # No signature help at the position closes the one showing
      request = request_signature_help["help2"]
      master.result_controller.process_response({ id: request.message[:id], result: { signature_help: nil, syntax_error: false } })
      assert_equal(
        [Master::SendMessageJob.to_client(message: { id: "help2", result: nil })],
        flush_queue(master.write_queue)
      )

      # A syntax error while the client shows a signature help is answered with the one showing, as the client sent it
      active_signature_help = {
        signatures: [{ label: "(::String) -> void", parameters: [{ label: "::String" }] }],
        activeSignature: 0,
        activeParameter: 0
      }
      request = request_signature_help["help3", { triggerKind: 3, isRetrigger: true, activeSignatureHelp: active_signature_help }]
      master.result_controller.process_response({ id: request.message[:id], result: { signature_help: nil, syntax_error: true } })
      assert_equal(
        [Master::SendMessageJob.to_client(message: { id: "help3", result: active_signature_help })],
        flush_queue(master.write_queue)
      )

      # A syntax error with no signature help showing is answered with nil
      request = request_signature_help["help4", { triggerKind: 2, triggerCharacter: "(", isRetrigger: false }]
      master.result_controller.process_response({ id: request.message[:id], result: { signature_help: nil, syntax_error: true } })
      assert_equal(
        [Master::SendMessageJob.to_client(message: { id: "help4", result: nil })],
        flush_queue(master.write_queue)
      )

      # ... and so is one from a client that sends no context
      request = request_signature_help["help5"]
      master.result_controller.process_response({ id: request.message[:id], result: { signature_help: nil, syntax_error: true } })
      assert_equal(
        [Master::SendMessageJob.to_client(message: { id: "help5", result: nil })],
        flush_queue(master.write_queue)
      )
    end
  end

  def test_interaction_request_goes_to_the_least_loaded_worker
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

      worker1 = Server::WorkerProcess.new(reader: nil, writer: nil, stderr: nil, wait_thread: nil, name: "test1", index: 0)
      worker2 = Server::WorkerProcess.new(reader: nil, writer: nil, stderr: nil, wait_thread: nil, name: "test2", index: 1)

      master = Server::Master.new(
        project: project,
        reader: worker_reader,
        writer: worker_writer,
        launcher: WorkersLauncher.new(worker1, worker2)
      )
      master.assign_initialize_params(DEFAULT_CLI_LSP_INITIALIZE_PARAMS)
      master.controller.load(command_line_args: [])

      request_hover = -> (id) do
        master.process_message_from_client(
          {
            method: "textDocument/hover",
            id: id,
            params: {
              textDocument: { uri: "#{file_scheme}#{current_dir}/lib/foo.rb" },
              position: { line: 0, character: 0 }
            }
          }
        )
        flush_queue(master.write_queue).find { |job| job.message[:method] == Hover::METHOD } or raise
      end

      # The worker with the fewest type check jobs in flight takes the request
      master.typecheck_jobs_in_flight[worker1] = 2
      request1 = request_hover["hover1"]
      assert_equal worker2, request1.dest
      assert_equal({ worker2 => 1 }, master.interaction_jobs_in_flight)

      # The interaction requests in flight count as the load, too
      master.typecheck_jobs_in_flight[worker1] = 0
      request2 = request_hover["hover2"]
      assert_equal worker1, request2.dest
      assert_equal({ worker2 => 1, worker1 => 1 }, master.interaction_jobs_in_flight)

      # The response frees the worker
      master.result_controller.process_response({ id: request1.message[:id], result: nil })
      assert_equal({ worker2 => 0, worker1 => 1 }, master.interaction_jobs_in_flight)

      request3 = request_hover["hover3"]
      assert_equal worker2, request3.dest
    end
  end

  def test_interaction_request_without_worker
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

      master = Server::Master.new(
        project: project,
        reader: worker_reader,
        writer: worker_writer,
        launcher: WorkersLauncher.new
      )
      master.assign_initialize_params(DEFAULT_CLI_LSP_INITIALIZE_PARAMS)
      master.controller.load(command_line_args: [])

      # Nothing answers hover, completion, and signature help
      master.process_message_from_client(
        {
          method: "textDocument/hover",
          id: "hover_id",
          params: {
            textDocument: { uri: "#{file_scheme}#{current_dir}/lib/foo.rb" },
            position: { line: 0, character: 0 }
          }
        }
      )
      assert_equal(
        [Master::SendMessageJob.to_client(message: { id: "hover_id", result: nil })],
        flush_queue(master.write_queue)
      )

      # Goto finds no location
      master.process_message_from_client(
        {
          method: "textDocument/definition",
          id: "definition_id",
          params: {
            textDocument: { uri: "#{file_scheme}#{current_dir}/lib/foo.rb" },
            position: { line: 0, character: 0 }
          }
        }
      )
      assert_equal(
        [Master::SendMessageJob.to_client(message: { id: "definition_id", result: [] })],
        flush_queue(master.write_queue)
      )
    end
  end

  def test_goto_definition_via_typecheck_worker
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

      typecheck_worker = Server::WorkerProcess.new(reader: nil, writer: nil, stderr: nil, wait_thread: nil, name: "test", index: 0)

      master = Server::Master.new(
        project: project,
        reader: worker_reader,
        writer: worker_writer,
        launcher: WorkersLauncher.new(typecheck_worker)
      )
      master.assign_initialize_params(DEFAULT_CLI_LSP_INITIALIZE_PARAMS)

      master.type_check_database.update_signature(
        path: current_dir + "sig/customer.rbs",
        target: :lib,
        diagnostics: [],
        entries: [
          Server::TypeCheckDatabase::Entry.new(name: "::Customer#name", role: :definition, start_line: 1, start_character: 6, end_line: 1, end_character: 10)
        ]
      )

      master.process_message_from_client(
        {
          method: "textDocument/definition",
          id: "definition_id",
          params: {
            textDocument: { uri: "#{file_scheme}#{current_dir}/lib/customer.rb" },
            position: { line: 3, character: 9 }
          }
        }
      )

      # The request is forwarded to the typecheck worker as `$/steep/source/symbol`
      jobs = flush_queue(master.write_queue)
      request = jobs.find { |job| job.message[:method] == Source__Symbol::METHOD } or raise
      assert_equal typecheck_worker, request.dest
      assert_equal(
        { uri: "#{file_scheme}#{current_dir}/lib/customer.rb", position: { line: 3, character: 9 } },
        request.message[:params]
      )

      # The symbols in the response are resolved with the database
      master.result_controller.process_response(
        { id: request.message[:id], result: { method_names: ["::Customer#name"], type: "::String" } }
      )

      assert_equal(
        [
          Master::SendMessageJob.to_client(
            message: {
              id: "definition_id",
              result: [
                {
                  uri: "#{file_scheme}#{current_dir}/sig/customer.rbs",
                  range: { start: { line: 1, character: 6 }, end: { line: 1, character: 10 } }
                }
              ]
            }
          )
        ],
        flush_queue(master.write_queue)
      )
    end
  end

  def test_stats_from_database
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

      master = Server::Master.new(
        project: project,
        reader: worker_reader,
        writer: worker_writer,
        launcher: WorkersLauncher.new
      )
      master.assign_initialize_params(DEFAULT_CLI_LSP_INITIALIZE_PARAMS)

      master.type_check_database.update_source(
        path: current_dir + "lib/customer.rb",
        target: :lib,
        diagnostics: [],
        entries: [],
        stats: { typed_calls: 3, untyped_calls: 1, error_calls: 0 }
      )
      master.type_check_database.update_source(path: current_dir + "lib/broken.rb", target: :lib, diagnostics: [], entries: [], stats: nil)
      master.type_check_database.update_signature(path: current_dir + "sig/customer.rbs", target: :lib, diagnostics: [], entries: [])

      master.process_message_from_client({ method: Stats::METHOD, id: "stats" })

      jobs = flush_queue(master.write_queue)
      assert_equal 1, jobs.size
      assert_equal "stats", jobs[0].message[:id]

      # The stats of the Ruby files, sorted by path, with the paths relative to the project
      assert_equal(
        [
          { type: "error", target: "lib", path: "lib/broken.rb" },
          { type: "success", target: "lib", path: "lib/customer.rb", typed_calls: 3, untyped_calls: 1, error_calls: 0, total_calls: 4 }
        ],
        jobs[0].message[:result]
      )
    end
  end

  def test_query_diagnostics_from_database
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

      master = Server::Master.new(
        project: project,
        reader: worker_reader,
        writer: worker_writer,
        launcher: WorkersLauncher.new
      )
      master.assign_initialize_params(DEFAULT_CLI_LSP_INITIALIZE_PARAMS)

      diagnostic = { message: "error", range: { start: { line: 0, character: 0 }, end: { line: 0, character: 1 } } }
      master.type_check_database.update_source(path: current_dir + "lib/customer.rb", target: :lib, diagnostics: [diagnostic], entries: [])
      master.type_check_database.update_signature(path: current_dir + "sig/customer.rbs", target: :lib, diagnostics: [], entries: [])

      # The requested files, with `nil` for a file that is not type checked
      master.process_message_from_client(
        {
          method: Query__Diagnostics::METHOD,
          id: "query1",
          params: { paths: [(current_dir + "lib/customer.rb").to_s, (current_dir + "lib/other.rb").to_s] }
        }
      )

      jobs = flush_queue(master.write_queue)
      response = jobs.find { _1.message[:id] == "query1" } or raise
      assert_equal(
        [
          { uri: "#{file_scheme}#{current_dir}/lib/customer.rb", diagnostics: [diagnostic] },
          { uri: "#{file_scheme}#{current_dir}/lib/other.rb", diagnostics: nil }
        ],
        response.message[:result]
      )

      # Every type checked file
      master.process_message_from_client({ method: Query__Diagnostics::METHOD, id: "query2", params: { paths: nil } })

      jobs = flush_queue(master.write_queue)
      response = jobs.find { _1.message[:id] == "query2" } or raise
      assert_equal(
        [
          { uri: "#{file_scheme}#{current_dir}/lib/customer.rb", diagnostics: [diagnostic] },
          { uri: "#{file_scheme}#{current_dir}/sig/customer.rbs", diagnostics: [] }
        ],
        response.message[:result]
      )
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
        launcher: WorkersLauncher.new(worker)
      )
      master.assign_initialize_params(DEFAULT_CLI_LSP_INITIALIZE_PARAMS)

      master.controller.add_dirty_code_path current_dir + "lib/customer.rb"
      master.controller.add_dirty_code_path current_dir + "lib/account.rb"

      progress = master.work_done_progress("guid")
      master.start_type_check(last_request: nil, progress: progress, report_progress_threshold: 0, needs_response: true)

      assert_instance_of Server::TypeCheckController::Request, master.current_type_check_request

      flush_queue(master.write_queue)

      master.on_type_check_update(guid: "guid", path: current_dir + "lib/customer.rb", target: project.targets[0], source: { diagnostics: [], entries: [] })
      master.on_type_check_update(guid: "guid", path: current_dir + "lib/account.rb", target: project.targets[0], source: { diagnostics: nil, entries: nil })

      jobs = flush_queue(master.write_queue)

      assert_equal 2, jobs.size
      assert_any!(jobs) do |job|
        # Response to $/steep/typecheck request
        assert_instance_of Master::SendMessageJob, job
        assert_equal :client, job.dest
        assert_equal "guid", job.message[:id]
      end
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
        launcher: WorkersLauncher.new(worker)
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
        launcher: WorkersLauncher.new(worker)
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
        launcher: WorkersLauncher.new(worker)
      )

      assert_empty master.controller.dirty_code_paths
      assert_empty master.controller.dirty_signature_paths
      assert_empty master.controller.dirty_inline_paths

      master.process_message_from_client(
        {
          method: "textDocument/didChange",
          params: {
            textDocument: {
              uri: "#{file_scheme}#{current_dir + "lib/customer.rb"}"
            },
            contentChanges: [
              { text: "class Customer\nend\n" }
            ]
          }
        }
      )

      # The change is not broadcast to the workers: they receive the contents with the requests
      jobs = flush_queue(master.write_queue)
      assert_empty jobs

      assert_operator master.controller.dirty_code_paths, :include?, current_dir + "lib/customer.rb"
      assert_equal "class Customer\nend\n", master.controller.file_contents.fetch(Pathname("lib/customer.rb")).text
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
        launcher: WorkersLauncher.new(worker)
      )

      assert_empty master.controller.dirty_code_paths
      assert_empty master.controller.dirty_signature_paths
      assert_empty master.controller.dirty_inline_paths

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

      jobs = flush_queue(master.write_queue)
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
        launcher: WorkersLauncher.new(worker)
      )

      assert_empty master.controller.open_paths

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

      assert_operator master.controller.open_paths, :include?, current_dir + "lib/customer.rb"

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

      refute_operator master.controller.open_paths, :include?, current_dir + "lib/customer.rb"
    end
  end


  def test_type_check_request__dispatch_across_workers
    in_tmpdir do
      steepfile = current_dir + "Steepfile"
      project = Project.new(steepfile_path: steepfile)
      Project::DSL.eval(project) do
        target :lib do
          check "lib"
          signature "sig"
        end
      end

      worker1 = Server::WorkerProcess.new(reader: nil, writer: nil, stderr: nil, wait_thread: nil, name: "test-1", index: 0)
      worker2 = Server::WorkerProcess.new(reader: nil, writer: nil, stderr: nil, wait_thread: nil, name: "test-2", index: 1)

      master = Server::Master.new(
        project: project,
        reader: worker_reader,
        writer: worker_writer,
        launcher: WorkersLauncher.new(worker1, worker2)
      )
      master.assign_initialize_params(DEFAULT_CLI_LSP_INITIALIZE_PARAMS)

      master.process_message_from_client({
        id: "guid",
        method: TypeCheck::METHOD,
        params: {
          library_paths: [],
          signature_paths: [],
          code_paths: [
            ["lib", (current_dir + "lib/a.rb").to_s],
            ["lib", (current_dir + "lib/b.rb").to_s],
            ["lib", (current_dir + "lib/c.rb").to_s]
          ],
          inline_paths: []
        }
      })

      # Each worker takes one file per round, so the files are spread across the workers from the start
      jobs = flush_queue(master.write_queue).select { _1.message[:method] == TypeCheck__File::METHOD }
      assert_equal(
        [
          ["test-1", Steep::PathHelper.to_uri(current_dir + "lib/a.rb").to_s],
          ["test-2", Steep::PathHelper.to_uri(current_dir + "lib/b.rb").to_s],
          ["test-1", Steep::PathHelper.to_uri(current_dir + "lib/c.rb").to_s]
        ],
        jobs.map { [_1.dest.name, _1.message[:params][:uri]] }
      )
    end
  end

  def test_type_check_request__no_jobs_after_shutdown
    in_tmpdir do
      steepfile = current_dir + "Steepfile"
      project = Project.new(steepfile_path: steepfile)
      Project::DSL.eval(project) do
        target :lib do
          check "lib"
          signature "sig"
        end
      end

      worker = Server::WorkerProcess.new(reader: nil, writer: nil, stderr: nil, wait_thread: nil, name: "test", index: 0)

      master = Server::Master.new(
        project: project,
        reader: worker_reader,
        writer: worker_writer,
        launcher: WorkersLauncher.new(worker)
      )
      master.assign_initialize_params(DEFAULT_CLI_LSP_INITIALIZE_PARAMS)

      master.process_message_from_client({
        id: "guid",
        method: TypeCheck::METHOD,
        params: {
          library_paths: [["lib", "/rbs/core/object.rbs"]],
          signature_paths: [["lib", (current_dir + "sig/customer.rbs").to_s]],
          code_paths: [["lib", (current_dir + "lib/customer.rb").to_s]],
          inline_paths: []
        }
      })

      jobs = flush_queue(master.write_queue).select { _1.dest == worker }
      assert_equal [TypeCheck__File::METHOD] * 2, jobs.map { _1.message[:method] }

      # The client shuts the server down while the type check is running: the workers hear nothing until `exit`
      master.process_message_from_client({ id: "shutdown", method: "shutdown", params: nil })
      assert_equal [{ id: "shutdown", result: nil }], flush_queue(master.write_queue).map { _1.message }

      # The response to a job sends no more job to the worker
      master.result_controller.process_response({ id: jobs[0].message[:id], result: { source: { diagnostics: [], entries: [], stats: nil }, signature: nil } })
      assert_empty flush_queue(master.write_queue).select { _1.dest == worker }
    end
  end

  def test_type_check_request__start
    in_tmpdir do
      steepfile = current_dir + "Steepfile"
      project = Project.new(steepfile_path: steepfile)
      Project::DSL.eval(project) do
        target :lib do
          check "lib"
          signature "sig"
        end
      end

      worker = Server::WorkerProcess.new(reader: nil, writer: nil, stderr: nil, wait_thread: nil, name: "test", index: 0)

      master = Server::Master.new(
        project: project,
        reader: worker_reader,
        writer: worker_writer,
        launcher: WorkersLauncher.new(worker)
      )
      master.assign_initialize_params(DEFAULT_CLI_LSP_INITIALIZE_PARAMS)

      master.process_message_from_client({
        id: "guid",
        method: TypeCheck::METHOD,
        params: {
          library_paths: [["lib", "/rbs/core/object.rbs"]],
          signature_paths: [["lib", (current_dir + "sig/customer.rbs").to_s]],
          code_paths: [["lib", (current_dir + "lib/customer.rb").to_s]],
          inline_paths: []
        }
      })

      refute_nil master.current_type_check_request

      # The worker gets `TYPECHECK_JOBS_PER_WORKER` requests first: the Ruby file, then the RBS file
      jobs = flush_queue(master.write_queue).select { _1.dest == worker }
      assert_equal [TypeCheck__File::METHOD] * 2, jobs.map { _1.message[:method] }
      assert_equal(
        [
          { guid: "guid", kind: "code", target: "lib", uri: Steep::PathHelper.to_uri(current_dir + "lib/customer.rb").to_s },
          { guid: "guid", kind: "signature", target: "lib", uri: Steep::PathHelper.to_uri(current_dir + "sig/customer.rbs").to_s }
        ],
        jobs.map { _1.message[:params] }
      )

      # The library file goes out when a response comes back
      master.result_controller.process_response({ id: jobs[0].message[:id], result: { source: { diagnostics: [], entries: [], stats: nil }, signature: nil } })
      jobs = flush_queue(master.write_queue).select { _1.dest == worker }
      assert_equal(
        [{ guid: "guid", kind: "library", target: "lib", uri: Steep::PathHelper.to_uri("/rbs/core/object.rbs").to_s }],
        jobs.map { _1.message[:params] }
      )
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

      launcher = Server::SpawnLauncher.new(steepfile: steepfile, steep_command: nil, typecheck_count: 1)

      master = Server::Master.new(
        project: project,
        reader: worker_reader,
        writer: worker_writer,
        launcher: launcher
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
            ui.diagnostics_for(project.absolute_path(Pathname("lib/foo.rb")))&.map { _1.except(:codeDescription) }
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
            ui.diagnostics_for(project.absolute_path(Pathname("lib/bar.rb")))&.map { _1.except(:codeDescription) }
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

      launcher = Server::SpawnLauncher.new(steepfile: steepfile, steep_command: nil, typecheck_count: 1)

      master = Server::Master.new(project: project,
                                  reader: worker_reader,
                                  writer: worker_writer,
                                  launcher: launcher)

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
            ui.diagnostics_for(project.absolute_path(Pathname("lib/foo.rb")))&.map { _1.except(:codeDescription) }
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

      launcher = Server::SpawnLauncher.new(steepfile: steepfile, steep_command: nil, typecheck_count: 2)

      master = Server::Master.new(project: project,
                                  reader: worker_reader,
                                  writer: worker_writer,
                                  launcher: launcher)

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

      launcher = Server::SpawnLauncher.new(steepfile: steepfile, steep_command: nil, typecheck_count: 2)

      master = Server::Master.new(project: project,
                                  reader: worker_reader,
                                  writer: worker_writer,
                                  launcher: launcher)

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
        launcher: WorkersLauncher.new(worker)
      )

      assert_empty master.controller.dirty_code_paths
      assert_empty master.controller.dirty_signature_paths
      assert_empty master.controller.dirty_inline_paths

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

      jobs = flush_queue(master.write_queue)
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
        flush_queue(master.write_queue)
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
        flush_queue(master.write_queue)
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
        flush_queue(master.write_queue)
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
        flush_queue(master.write_queue)
      )
    end
  end

  def test_type_check_request__empty
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

      launcher = Server::SpawnLauncher.new(steepfile: steepfile, steep_command: nil, typecheck_count: 1)

      master = Server::Master.new(
        project: project,
        reader: worker_reader,
        writer: worker_writer,
        launcher: launcher
      )

      main_thread = Thread.new do
        Thread.current.abort_on_exception = true
        master.start()
      end

      master_writer.write({
        id: "initialize-id",
        method: "initialize",
        params: DEFAULT_CLI_LSP_INITIALIZE_PARAMS
      })

      master_reader.read do |message|
        break if message[:id] == "initialize-id"
      end

      master_writer.write({
        id: "typecheck-id",
        method: TypeCheck::METHOD,
        params: {
          code_paths: [],
          signature_paths: [],
          library_paths: [],
          inline_paths: []
        }
      })

      master_reader.read do |message|
        break if message[:id] == "typecheck-id"
      end

      master_writer.write({
        id: "shutdown-id",
        method: "shutdown",
        params: nil
      })

      master_reader.read do |message|
        break if message[:id] == "shutdown-id"
      end

      master_writer.write({ method: "exit" })

      main_thread.join
    end
  end

  def test_type_check_request__type_check
    in_tmpdir do
      steepfile = current_dir + "Steepfile"
      steepfile.write(<<-EOF)
target :lib do
  check "lib"
  signature "sig"
end
      EOF

      (current_dir + "lib").mkpath
      (current_dir + "sig").mkpath

      (current_dir + "lib/customer.rb").write(<<~RUBY)
        class Customer
        end
      RUBY
      (current_dir + "sig/customer.rbs").write(<<~RBS)
        class Customer
        end
      RBS

      project = Project.new(steepfile_path: steepfile)
      Project::DSL.parse(project, steepfile.read)

      launcher = Server::SpawnLauncher.new(steepfile: steepfile, steep_command: nil, typecheck_count: 1)

      master = Server::Master.new(
        project: project,
        reader: worker_reader,
        writer: worker_writer,
        launcher: launcher
      )

      main_thread = Thread.new do
        Thread.current.abort_on_exception = true
        master.start()
      end

      master_writer.write({
        id: "initialize-id",
        method: "initialize",
        params: DEFAULT_CLI_LSP_INITIALIZE_PARAMS
      })

      master_reader.read do |message|
        break if message[:id] == "initialize-id"
      end

      master_writer.write({
        id: "typecheck-id",
        method: TypeCheck::METHOD,
        params: {
          code_paths: [["lib", (current_dir + "lib/customer.rb").to_s]],
          signature_paths: [["lib", (current_dir + "sig/customer.rbs").to_s]],
          library_paths: [],
          inline_paths: []
        }
      })

      diagnostics = {}

      master_reader.read do |message|
        break if message[:id] == "typecheck-id"

        if message[:method] == "textDocument/publishDiagnostics"
          diagnostics[Steep::PathHelper.to_pathname(message[:params][:uri])] = message[:params][:diagnostics]
        end
      end

      assert_operator diagnostics, :key?, current_dir + "lib/customer.rb"
      assert_operator diagnostics, :key?, current_dir + "sig/customer.rbs"

      master_writer.write({
        id: "shutdown-id",
        method: "shutdown",
        params: nil
      })

      master_reader.read do |message|
        break if message[:id] == "shutdown-id"
      end

      master_writer.write({ method: "exit" })

      main_thread.join
    end
  end

  def test__initialize__file_system_watcher_setup
    in_tmpdir do
      steepfile = current_dir + "Steepfile"
      steepfile.write(<<-EOF)
target :lib do
  group :core do
    check "lib/core"
  end

  check "lib"
end
      EOF

      project = Project.new(steepfile_path: steepfile)
      Project::DSL.parse(project, steepfile.read)

      worker = Server::WorkerProcess.new(reader: nil, writer: nil, stderr: nil, wait_thread: nil, name: "test", index: 0)

      master = Server::Master.new(
        project: project,
        reader: worker_reader,
        writer: worker_writer,
        launcher: WorkersLauncher.new(worker)
      )
      master.assign_initialize_params(
        DEFAULT_CLI_LSP_INITIALIZE_PARAMS.merge(
          {
            capabilities: {
              workspace: {
                didChangeWatchedFiles: {
                  dynamicRegistration: true
                }
              }
            }
          }
        )
      )

      master.setup_file_system_watcher()

      jobs = flush_queue(master.write_queue)

      jobs.find { _1.message[:method] == "client/registerCapability" }.tap do |job|
        job.message[:params][:registrations].find { _1[:method] == "workspace/didChangeWatchedFiles" }.tap do |registration|
          watchers = registration[:registerOptions][:watchers]

          assert_includes(watchers, { globPattern: "#{current_dir}/lib/**/*.rb" })
          assert_includes(watchers, { globPattern: "#{current_dir}/lib/core/**/*.rb" })
        end
      end
    end
  end

  def test_library_entries_loaded_on_initialize
    in_tmpdir do
      steepfile = current_dir + "Steepfile"
      steepfile.write(<<-EOF)
target :lib do
  check "lib"
  signature "sig"
end

target :test do
  check "test"
  signature "sig/test"
end
      EOF

      (current_dir + "lib").mkpath
      (current_dir + "sig/test").mkpath
      (current_dir + "sig/customer.rbs").write("class Customer\nend\n")

      project = Project.new(steepfile_path: steepfile)
      Project::DSL.parse(project, steepfile.read)

      worker = Server::WorkerProcess.new(reader: nil, writer: nil, stderr: nil, wait_thread: nil, name: "test", index: 0)

      master = Server::Master.new(
        project: project,
        reader: worker_reader,
        writer: worker_writer,
        launcher: WorkersLauncher.new(worker)
      )

      master.process_message_from_client({ id: "initialize", method: "initialize", params: DEFAULT_CLI_LSP_INITIALIZE_PARAMS })
      flush_queue(master.write_queue)

      # The entries of the library RBS files are collected in the environment thread, and stored in the main thread
      assert_equal [], master.type_check_database.definitions("::String")
      master.environment_queue.pop.call
      master.job_queue.pop.call

      assert_any!(master.type_check_database.definitions("::String")) do |location|
        assert_equal :rbs, location.source
        assert_operator location.path.to_s, :end_with?, "/core/string.rbs"
        refute master.type_check_database.checked?(location.path)
      end

      # The project RBS files are not in the database until the workers validate them
      assert_equal [], master.type_check_database.definitions("::Customer")

      # The entries collected in the environments of the two targets are merged: the core RBS files are stored once
      service = master.controller.type_check_service or raise
      entries = Server::TypeCheckDatabase.rbs_entries_by_path(service.signature_services.fetch(:lib).latest_env)
      assert_equal entries.sum { |_, entries| entries.size }, master.type_check_database.entry_count

      master.process_message_from_client({ id: "definition", method: Query__Definition::METHOD, params: { name: "::String" } })
      jobs = flush_queue(master.write_queue)
      assert_equal "type_name", jobs[0].message[:result][:kind]
      assert_any!(jobs[0].message[:result][:locations]) do |location|
        assert_equal "rbs", location[:source]
        assert_operator location[:uri], :end_with?, "/core/string.rbs"
      end
    end
  end

  def test_start_type_check_delivers_file_contents
    in_tmpdir do
      steepfile = current_dir + "Steepfile"
      steepfile.write(<<-EOF)
target :lib do
  check "lib"
  signature "sig"
end
      EOF

      (current_dir + "lib").mkpath
      (current_dir + "sig").mkpath
      (current_dir + "lib/customer.rb").write("class Customer\nend\n")
      (current_dir + "lib/account.rb").write("class Account\nend\n")
      (current_dir + "sig/customer.rbs").write("class Customer\nend\n")

      project = Project.new(steepfile_path: steepfile)
      Project::DSL.parse(project, steepfile.read)

      worker = Server::WorkerProcess.new(reader: nil, writer: nil, stderr: nil, wait_thread: nil, name: "test", index: 0)

      master = Server::Master.new(
        project: project,
        reader: worker_reader,
        writer: worker_writer,
        launcher: WorkersLauncher.new(worker)
      )

      master.process_message_from_client({ id: "initialize", method: "initialize", params: DEFAULT_CLI_LSP_INITIALIZE_PARAMS })
      flush_queue(master.write_queue)

      # The worker receives the RBS files before the type check, and the Ruby file with its request
      master.process_message_from_client({
        id: "check-1",
        method: TypeCheck::METHOD,
        params: {
          library_paths: [],
          signature_paths: [["lib", (current_dir + "sig/customer.rbs").to_s]],
          code_paths: [["lib", (current_dir + "lib/customer.rb").to_s]],
          inline_paths: []
        }
      })

      jobs = flush_queue(master.write_queue).select { _1.dest == worker }
      assert_equal [FileLoad::METHOD, TypeCheck__File::METHOD, TypeCheck__File::METHOD], jobs.map { _1.message[:method] }
      assert_equal({ "sig/customer.rbs" => "class Customer\nend\n" }, jobs[0].message[:params][:content])
      assert_equal "code", jobs[1].message[:params][:kind]
      assert_equal "class Customer\nend\n", jobs[1].message[:params][:content]
      assert_equal "signature", jobs[2].message[:params][:kind]
      refute_operator jobs[2].message[:params], :key?, :content

      jobs.drop(1).each do |job|
        master.result_controller.process_response({ id: job.message[:id], result: { source: nil, signature: nil } })
      end
      flush_queue(master.write_queue)

      # A file the worker already has is not sent again, and a changed file is sent with the new content
      master.process_message_from_client(
        {
          method: "textDocument/didChange",
          params: {
            textDocument: { uri: "#{file_scheme}#{current_dir + "lib/customer.rb"}" },
            contentChanges: [{ text: "class Customer\n  def name = \"\"\nend\n" }]
          }
        }
      )
      master.process_message_from_client({
        id: "check-2",
        method: TypeCheck::METHOD,
        params: {
          library_paths: [],
          signature_paths: [["lib", (current_dir + "sig/customer.rbs").to_s]],
          code_paths: [["lib", (current_dir + "lib/customer.rb").to_s], ["lib", (current_dir + "lib/account.rb").to_s]],
          inline_paths: []
        }
      })

      jobs = flush_queue(master.write_queue).select { _1.dest == worker }
      assert_equal [TypeCheck__File::METHOD, TypeCheck__File::METHOD], jobs.map { _1.message[:method] }
      assert_equal(
        [
          ["code", Steep::PathHelper.to_uri(current_dir + "lib/customer.rb").to_s, "class Customer\n  def name = \"\"\nend\n"],
          ["code", Steep::PathHelper.to_uri(current_dir + "lib/account.rb").to_s, "class Account\nend\n"]
        ],
        jobs.map { |job| params = job.message[:params]; [params[:kind], params[:uri], params[:content]] }
      )
    end
  end
end
