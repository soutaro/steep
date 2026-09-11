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
        assert_equal TypeCheck__Start::METHOD, job.message[:method]

        job.message[:params].tap do |params|
          assert_equal "guid", params[:guid]
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

        assert_equal TypeCheck__Start::METHOD, job.message[:method]

        job.message[:params].tap do |params|
          assert_equal "guid", params[:guid]
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
      master.assign_initialize_params(DEFAULT_CLI_LSP_INITIALIZE_PARAMS)

      master.controller.add_dirty_code_path current_dir + "lib/customer.rb"
      master.controller.add_dirty_code_path current_dir + "lib/account.rb"

      progress = master.work_done_progress("guid")
      master.start_type_check(last_request: nil, progress: progress, report_progress_threshold: 10, needs_response: true)

      refute_nil master.current_type_check_request

      jobs = flush_queue(master.write_queue)

      assert_any!(jobs, size: 1) do |job|
        assert_instance_of Master::SendMessageJob, job
        assert_equal worker, job.dest
        assert_equal TypeCheck__Start::METHOD, job.message[:method]

        job.message[:params].tap do |params|
          assert_equal "guid", params[:guid]
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
        interaction_worker: nil,
        typecheck_workers: [worker]
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

  def test_goto_definition_via_interaction_worker
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

      interaction_worker = Server::WorkerProcess.new(reader: nil, writer: nil, stderr: nil, wait_thread: nil, name: "interaction", index: nil)
      typecheck_worker = Server::WorkerProcess.new(reader: nil, writer: nil, stderr: nil, wait_thread: nil, name: "test", index: 0)

      master = Server::Master.new(
        project: project,
        reader: worker_reader,
        writer: worker_writer,
        interaction_worker: interaction_worker,
        typecheck_workers: [typecheck_worker]
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

      # The request is forwarded to the interaction worker as `$/steep/source/symbol`
      jobs = flush_queue(master.write_queue)
      request = jobs.find { |job| job.message[:method] == Source__Symbol::METHOD } or raise
      assert_equal interaction_worker, request.dest
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
        interaction_worker: nil,
        typecheck_workers: []
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

      # The stats of the Ruby files, with the paths relative to the project
      assert_equal(
        [
          { type: "success", target: "lib", path: "lib/customer.rb", typed_calls: 3, untyped_calls: 1, error_calls: 0, total_calls: 4 },
          { type: "error", target: "lib", path: "lib/broken.rb" }
        ],
        jobs[0].message[:result].sort_by { _1[:path] }.reverse
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
        interaction_worker: nil,
        typecheck_workers: []
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
        interaction_worker: nil,
        typecheck_workers: [worker]
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

      assert_empty master.controller.dirty_code_paths
      assert_empty master.controller.dirty_signature_paths
      assert_empty master.controller.dirty_inline_paths

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

      jobs = flush_queue(master.write_queue)

      assert_any!(jobs, size: 1) do |job|
        assert_instance_of Master::SendMessageJob, job
        assert_equal worker, job.dest
        assert_equal "textDocument/didChange", job.message[:method]
      end

      assert_operator master.controller.dirty_code_paths, :include?, current_dir + "lib/customer.rb"
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
        interaction_worker: nil,
        typecheck_workers: [worker]
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
        interaction_worker: nil,
        typecheck_workers: [worker]
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

      jobs = flush_queue(master.write_queue)

      assert_any!(jobs, size: 1) do |job|
        assert_instance_of Master::SendMessageJob, job
        assert_equal worker, job.dest
        assert_equal TypeCheck__Start::METHOD, job.message[:method]

        job.message[:params].tap do |params|
          assert_equal "guid", params[:guid]
          assert_equal [["lib", Steep::PathHelper.to_uri("/rbs/core/object.rbs").to_s]], params[:library_uris]
          assert_equal [["lib", Steep::PathHelper.to_uri(current_dir + "sig/customer.rbs").to_s]], params[:signature_uris]
          assert_equal [["lib", Steep::PathHelper.to_uri(current_dir + "lib/customer.rb").to_s]], params[:code_uris]
          assert_equal [], params[:priority_uris]
        end
      end
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

      typecheck_workers = Server::WorkerProcess.start_typecheck_workers(steepfile: steepfile, count: 1, args: [], steep_command: nil)

      master = Server::Master.new(
        project: project,
        reader: worker_reader,
        writer: worker_writer,
        interaction_worker: nil,
        typecheck_workers: typecheck_workers
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

      typecheck_workers = Server::WorkerProcess.start_typecheck_workers(steepfile: steepfile, count: 1, args: [], steep_command: nil)

      master = Server::Master.new(
        project: project,
        reader: worker_reader,
        writer: worker_writer,
        interaction_worker: nil,
        typecheck_workers: typecheck_workers
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
        interaction_worker: nil,
        typecheck_workers: [worker]
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
end
