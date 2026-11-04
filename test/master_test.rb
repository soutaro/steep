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

      worker = Server::WorkerProcess.new(reader: nil, writer: nil, stderr: nil, wait_thread: nil, name: "test")
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

  def test_fork_workers_on_initialize
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
      (current_dir + "sig/customer.rbs").write("class Customer\nend\n")

      project = Project.new(steepfile_path: steepfile)
      Project::DSL.parse(project, steepfile.read)

      worker = Server::WorkerProcess.new(reader: nil, writer: nil, stderr: nil, wait_thread: nil, name: "test")
      launcher = ForkedWorkersLauncher.new(worker)

      master = Server::Master.new(
        project: project,
        reader: worker_reader,
        writer: worker_writer,
        launcher: launcher
      )

      assert_empty master.typecheck_workers

      master.process_message_from_client({ id: "initialize", method: "initialize", params: DEFAULT_CLI_LSP_INITIALIZE_PARAMS })

      # The workers are forked from the environments with the files of the project
      assert_same master.controller.type_check_service, launcher.started_service
      assert (launcher.started_environments || raise).fetch(:lib).class_decls.key?(RBS::TypeName.parse("::Customer"))
      assert_equal [worker], master.typecheck_workers

      # The worker has the files, and receives nothing
      assert_empty flush_queue(master.write_queue).select { _1.dest == worker }

      # The environment thread indexes the RBS files of the project, and then the libraries
      run_environment_jobs(master)
      assert_equal [[current_dir + "sig/customer.rbs", 0]], master.type_check_database.definitions("::Customer").map { [_1.path, _1.start_line] }
      refute_empty master.type_check_database.definitions("::String")

      # A Ruby file changed after the fork is sent to the worker with its request
      master.controller.push_file_change(current_dir + "lib/customer.rb", "class Customer\n  def name = \"\"\nend\n")
      master.process_message_from_client({
        id: "check",
        method: TypeCheck::METHOD,
        params: {
          library_paths: [],
          signature_paths: [],
          code_paths: [["lib", (current_dir + "lib/customer.rb").to_s]],
          inline_paths: []
        }
      })

      jobs = flush_queue(master.write_queue).select { _1.dest == worker }
      assert_equal [TypeCheck__File::METHOD], jobs.map { _1.message[:method] }
      assert_equal "class Customer\n  def name = \"\"\nend\n", jobs[0].message[:params][:content]
    end
  end

  # Sets up a project with `lib/customer.rb` and `sig/customer.rbs`, and a master with `ForkedWorkersLauncher` that forks
  # one worker of each generation, after `initialize` and the indexing
  #
  # @rbs () { (Server::Master, LSPTestHelper::ForkedWorkersLauncher, Array[Server::WorkerProcess]) -> void } -> void
  def with_forked_master
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
      (current_dir + "sig/customer.rbs").write("class Customer\nend\n")

      project = Project.new(steepfile_path: steepfile)
      Project::DSL.parse(project, steepfile.read)

      workers = 3.times.map { Server::WorkerProcess.new(reader: nil, writer: nil, stderr: nil, wait_thread: nil, name: "test@#{_1}") }
      launcher = ForkedWorkersLauncher.new(*workers, typecheck_count: 1)

      master = Server::Master.new(
        project: project,
        reader: worker_reader,
        writer: worker_writer,
        launcher: launcher
      )
      master.typecheck_automatically = false

      master.process_message_from_client({ id: "initialize", method: "initialize", params: DEFAULT_CLI_LSP_INITIALIZE_PARAMS })
      flush_queue(master.write_queue)
      run_environment_jobs(master)

      yield master, launcher, workers
    end
  end

  # Runs the job of the environment thread, and the jobs it gives to the main loop
  #
  # @rbs (Server::Master, ^() -> void) -> void
  def run_environment_job(master, job)
    environment_thread = Thread.new { job.call }
    environment_thread.report_on_exception = false

    # The job waits for the main loop only when it forks the workers
    until environment_thread.join(0.01)
      if main_job = (master.job_queue.pop(timeout: 0.01) rescue nil)
        main_job.call
      end
    end

    until master.job_queue.empty?
      master.job_queue.pop.call
    end
  end

  # @rbs (Server::Master, Pathname) -> void
  def request_type_check(master, path)
    master.process_message_from_client({
      id: "check-#{SecureRandom.uuid}",
      method: TypeCheck::METHOD,
      params: {
        library_paths: [],
        signature_paths: [["lib", path.to_s]],
        code_paths: [],
        inline_paths: []
      }
    })
  end

  def test_refork_workers_on_signature_change
    with_forked_master do |master, launcher, workers|
      assert_equal [workers[0]], master.typecheck_workers

      # A type check job is in flight on the worker
      master.process_message_from_client({
        id: "check-code",
        method: TypeCheck::METHOD,
        params: { library_paths: [], signature_paths: [], code_paths: [["lib", (current_dir + "lib/customer.rb").to_s]], inline_paths: [] }
      })
      job = flush_queue(master.write_queue).find { _1.message[:method] == TypeCheck__File::METHOD } or raise
      assert_equal workers[0], job.dest

      # A change of the declarations in an RBS file retires the workers, and the jobs wait for the next generation
      master.controller.push_file_change(current_dir + "sig/customer.rbs", "class Customer\n  def name: () -> String\nend\n")
      request_type_check(master, current_dir + "sig/customer.rbs")

      assert_empty master.typecheck_workers
      assert_equal [workers[0]], launcher.retired_workers
      assert_empty flush_queue(master.write_queue).select { _1.dest.is_a?(Server::WorkerProcess) }
      refute_empty master.pending_typecheck_jobs

      # The retired worker finishes its job, and is not told to exit yet
      assert_equal [workers[0]], master.retiring_workers
      assert_empty master.exiting_workers.to_a

      # The next generation is forked from the environments updated with the change
      environment_jobs = flush_queue(master.environment_queue)
      assert_equal 1, environment_jobs.size
      run_environment_job(master, environment_jobs[0])

      assert_equal 2, launcher.start_count
      customer = (launcher.started_environments || raise).fetch(:lib).class_decls.fetch(RBS::TypeName.parse("::Customer"))
      assert customer.primary_decl.members.any? { _1.is_a?(RBS::AST::Members::MethodDefinition) && _1.name == :name }
      assert_equal [workers[1]], master.typecheck_workers
      assert_equal [[current_dir + "sig/customer.rbs", 1]], master.type_check_database.definitions("::Customer#name").map { [_1.path, _1.start_line] }

      # The new worker gets the jobs without the RBS file, and the retired worker finishing its job stays
      jobs = flush_queue(master.write_queue)
      assert_equal [workers[1]], jobs.map(&:dest).uniq
      assert_equal [TypeCheck__File::METHOD], jobs.map { _1.message[:method] }.uniq
      assert_equal [workers[1], workers[0]], master.each_worker.to_a

      # The retired worker is told to exit once its job is done
      master.result_controller.process_response({ id: job.message[:id], result: nil })
      jobs = flush_queue(master.write_queue)
      assert_equal [[workers[0], "exit"]], jobs.filter_map { [_1.dest, _1.message[:method]] if _1.dest.is_a?(Server::WorkerProcess) }
      assert_equal [workers[0]], master.exiting_workers.to_a
      assert_empty master.retiring_workers
    end
  end

  def test_refork_workers_when_update_fails
    with_forked_master do |master, launcher, workers|
      master.controller.push_file_change(current_dir + "sig/customer.rbs", "class Customer\n  def name: () -> String\nend\n")
      request_type_check(master, current_dir + "sig/customer.rbs")

      service = master.controller.type_check_service or raise
      service.define_singleton_method(:update) {|changes:| raise "Boom" }

      environment_jobs = flush_queue(master.environment_queue)
      assert_raises(RuntimeError) { run_environment_job(master, environment_jobs[0]) }

      # The workers are forked anyway, with the environments as they are, and get the jobs
      assert_equal [workers[1]], master.typecheck_workers

      jobs = flush_queue(master.write_queue).select { _1.dest == workers[1] }
      assert_equal [TypeCheck__File::METHOD], jobs.map { _1.message[:method] }
    end
  end

  def test_refork_workers_once_for_successive_changes
    with_forked_master do |master, launcher, workers|
      master.controller.push_file_change(current_dir + "sig/customer.rbs", "class Customer\n  def name: () -> String\nend\n")
      request_type_check(master, current_dir + "sig/customer.rbs")
      master.controller.push_file_change(current_dir + "sig/customer.rbs", "class Customer\n  def name: () -> String\n  def id: () -> Integer\nend\n")
      request_type_check(master, current_dir + "sig/customer.rbs")

      environment_jobs = flush_queue(master.environment_queue)
      assert_equal 2, environment_jobs.size

      # The first update doesn't fork the workers, which the second update asks for again
      environment_jobs[0].call
      assert_equal 1, launcher.start_count
      assert_empty master.typecheck_workers

      run_environment_job(master, environment_jobs[1])
      assert_equal 2, launcher.start_count
      assert_equal [workers[1]], master.typecheck_workers

      # The retired worker had no job, and was told to exit when it retired
      assert_equal [workers[0]], master.exiting_workers.to_a
    end
  end

  def test_keep_workers_on_signature_change_without_declarations
    with_forked_master do |master, launcher, workers|
      path = current_dir + "sig/customer.rbs"

      # A change that leaves the declarations as they are keeps the workers, which don't have the change
      master.controller.push_file_change(path, "# The customer\nclass Customer\nend\n")
      request_type_check(master, path)

      assert_equal [workers[0]], master.typecheck_workers
      assert_empty launcher.retired_workers
      assert_equal Set[path], master.signature_paths_to_validate

      # The master validates the file on the environment thread instead of the worker, and indexes it
      assert_empty flush_queue(master.write_queue).select { _1.dest.is_a?(Server::WorkerProcess) }
      assert_empty master.pending_typecheck_jobs
      refute_nil master.current_type_check_request

      run_environment_jobs(master)
      assert_equal 1, launcher.start_count
      assert_nil master.current_type_check_request
      assert_equal [], master.type_check_database.diagnostics(path)
      assert_equal [[path, 1]], master.type_check_database.definitions("::Customer").map { [_1.path, _1.start_line] }

      # A content that cannot be parsed keeps the workers too, and the master reports the error
      master.controller.push_file_change(path, "# The customer\nclass Customer\n  def\nend\n")
      request_type_check(master, path)
      assert_equal [workers[0]], master.typecheck_workers

      run_environment_jobs(master)
      assert_equal ["RBS::SyntaxError"], master.type_check_database.diagnostics(path).map { _1[:code] }

      # The next change of the declarations forks the workers again, which validate the file by themselves
      master.controller.push_file_change(path, "# The customer\nclass Customer\n  def name: () -> String\nend\n")
      request_type_check(master, path)
      assert_empty master.typecheck_workers
      assert_empty master.signature_paths_to_validate

      environment_jobs = flush_queue(master.environment_queue)
      assert_equal 1, environment_jobs.size
      run_environment_job(master, environment_jobs[0])

      assert_equal 2, launcher.start_count
      jobs = flush_queue(master.write_queue).select { _1.dest == workers[1] }
      assert_equal ["signature"], jobs.map { _1.message[:params][:kind] }
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

      worker = Server::WorkerProcess.new(reader: nil, writer: nil, stderr: nil, wait_thread: nil, name: "test")

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

      worker = Server::WorkerProcess.new(reader: nil, writer: nil, stderr: nil, wait_thread: nil, name: "test")

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

      worker = Server::WorkerProcess.new(reader: nil, writer: nil, stderr: nil, wait_thread: nil, name: "test")

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

      worker = Server::WorkerProcess.new(reader: nil, writer: nil, stderr: nil, wait_thread: nil, name: "test")

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

      worker = Server::WorkerProcess.new(reader: nil, writer: nil, stderr: nil, wait_thread: nil, name: "test")

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
          entries: nil
        }
      )

      database = master.type_check_database

      assert_equal [], database.diagnostics(current_dir + "lib/customer.rb")

      # The entries of the Ruby code are stored; the inline declarations are indexed from the environments
      definitions = database.definitions("::Customer#name")
      assert_equal [current_dir + "lib/customer.rb"], definitions.map(&:path).uniq
      assert_equal [[:ruby, 1]], definitions.map { [_1.source, _1.start_line] }

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

  # Runs the jobs on the environment queue, and then the jobs they hand to the main loop
  #
  # @rbs (Server::Master) -> void
  def run_environment_jobs(master)
    until master.environment_queue.empty?
      master.environment_queue.pop.call
    end

    until master.job_queue.empty?
      job = master.job_queue.pop
      job.call if job.is_a?(Proc)
    end
  end

  # A master with the project loaded, and no worker
  #
  # @rbs (Pathname steepfile) -> Server::Master
  def master_for_interaction(steepfile)
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

    master
  end

  def test_hover
    in_tmpdir do
      steepfile = current_dir + "Steepfile"
      steepfile.write(<<-EOF)
target :lib do
  check "lib"
  signature "sig"
end
      EOF
      (current_dir + "lib").mkpath
      (current_dir + "lib/foo.rb").write("xs = [1, 2]\n")

      master = master_for_interaction(steepfile)

      request_hover = -> (id, line, character) do
        master.process_message_from_client(
          {
            method: "textDocument/hover",
            id: id,
            params: {
              textDocument: { uri: "#{file_scheme}#{current_dir}/lib/foo.rb" },
              position: { line: line, character: character }
            }
          }
        )
      end

      # The interaction runs on the environment thread, which renders the result
      request_hover["hover_id", 0, 0]
      assert_empty flush_queue(master.write_queue)
      refute_empty master.environment_queue

      run_environment_jobs(master)

      jobs = flush_queue(master.write_queue)
      assert_equal 1, jobs.size
      jobs[0].tap do |job|
        assert_equal :client, job.dest
        assert_equal "hover_id", job.message[:id]

        hover = job.message[:result]
        assert_instance_of LSP::Interface::Hover, hover
        assert_equal({ start: { line: 0, character: 0 }, end: { line: 0, character: 2 } }.to_json, hover.range.to_json)
        assert_equal "**Local variable** `xs: ::Array[::Integer]`\n", hover.contents.value
      end

      # The interaction sees the changes received before it
      master.controller.push_file_change(current_dir + "lib/foo.rb", "xs = [\"a\"]\n")
      request_hover["hover_id2", 0, 0]
      run_environment_jobs(master)

      jobs = flush_queue(master.write_queue)
      assert_equal "**Local variable** `xs: ::Array[::String]`\n", jobs[0].message[:result].contents.value

      # Nothing at the position
      request_hover["hover_id3", 0, 12]
      run_environment_jobs(master)
      assert_equal(
        [Master::SendMessageJob.to_client(message: { id: "hover_id3", result: nil })],
        flush_queue(master.write_queue)
      )

      # Only the latest request is answered
      request_hover["hover_id4", 0, 0]
      request_hover["hover_id5", 0, 0]
      run_environment_jobs(master)

      jobs = flush_queue(master.write_queue)
      assert_equal ["hover_id4", "hover_id5"], jobs.map { _1.message[:id] }
      assert_nil jobs[0].message[:result]
      assert_instance_of LSP::Interface::Hover, jobs[1].message[:result]
    end
  end

  def test_signature_help
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
      (current_dir + "lib/foo.rb").write("Foo.new.foo(\"hello\")\n")
      (current_dir + "sig/foo.rbs").write("class Foo\n  def foo: (String name) -> void\nend\n")

      master = master_for_interaction(steepfile)

      request_signature_help = -> (id, character, context = nil) do
        params = {
          textDocument: { uri: "#{file_scheme}#{current_dir}/lib/foo.rb" },
          position: { line: 0, character: character }
        }
        params[:context] = context if context

        master.process_message_from_client({ method: "textDocument/signatureHelp", id: id, params: params })
        run_environment_jobs(master)
        flush_queue(master.write_queue)
      end

      # A signature help is rendered on the main thread
      jobs = request_signature_help["help1", 13]
      assert_equal 1, jobs.size
      help = jobs[0].message[:result]
      assert_instance_of LSP::Interface::SignatureHelp, help
      assert_equal ["(::String) -> void"], help.signatures.map(&:label)

      # No signature help at the position closes the one showing
      assert_equal(
        [Master::SendMessageJob.to_client(message: { id: "help2", result: nil })],
        request_signature_help["help2", 0]
      )

      # A syntax error while the client shows a signature help is answered with the one showing, as the client sent it
      master.controller.push_file_change(current_dir + "lib/foo.rb", "Foo.new.foo(\"hello\",\n")
      active_signature_help = {
        signatures: [{ label: "(::String) -> void", parameters: [{ label: "::String" }] }],
        activeSignature: 0,
        activeParameter: 0
      }
      assert_equal(
        [Master::SendMessageJob.to_client(message: { id: "help3", result: active_signature_help })],
        request_signature_help["help3", 20, { triggerKind: 3, isRetrigger: true, activeSignatureHelp: active_signature_help }]
      )

      # A syntax error with no signature help showing is answered with nil
      assert_equal(
        [Master::SendMessageJob.to_client(message: { id: "help4", result: nil })],
        request_signature_help["help4", 20, { triggerKind: 2, triggerCharacter: "(", isRetrigger: false }]
      )

      # ... and so is one from a client that sends no context
      assert_equal(
        [Master::SendMessageJob.to_client(message: { id: "help5", result: nil })],
        request_signature_help["help5", 20]
      )
    end
  end

  def test_interaction_request_before_load
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

      # Nothing answers hover, completion, and signature help before the project is loaded
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
      assert_empty master.environment_queue

      # Goto finds no location, on the main loop
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
      run_environment_jobs(master)
      assert_equal(
        [Master::SendMessageJob.to_client(message: { id: "definition_id", result: [] })],
        flush_queue(master.write_queue)
      )

      # A URI of no file is answered the same, after the project is loaded
      master.controller.load(command_line_args: [])
      master.process_message_from_client(
        {
          method: "textDocument/completion",
          id: "completion_id",
          params: {
            textDocument: { uri: "untitled:Untitled-1" },
            position: { line: 0, character: 0 }
          }
        }
      )
      assert_equal(
        [Master::SendMessageJob.to_client(message: { id: "completion_id", result: nil })],
        flush_queue(master.write_queue)
      )
      assert_empty master.environment_queue
    end
  end

  def test_goto_definition
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
      (current_dir + "lib/customer.rb").write("Customer.new.name\n")
      (current_dir + "sig/customer.rbs").write("class Customer\n  def name: () -> String\nend\n")

      master = master_for_interaction(steepfile)

      master.type_check_database.update_rbs(
        path: current_dir + "sig/customer.rbs",
        target: :lib,
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
            position: { line: 0, character: 14 }
          }
        }
      )

      # The symbol at the position is resolved on the environment thread, and looked up in the database
      run_environment_jobs(master)

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
      master.type_check_database.update_signature(path: current_dir + "sig/customer.rbs", target: :lib, diagnostics: [])

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
      master.type_check_database.update_signature(path: current_dir + "sig/customer.rbs", target: :lib, diagnostics: [])

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

      worker = Server::WorkerProcess.new(reader: nil, writer: nil, stderr: nil, wait_thread: nil, name: "test")

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

      worker = Server::WorkerProcess.new(reader: nil, writer: nil, stderr: nil, wait_thread: nil, name: "test")

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

      worker = Server::WorkerProcess.new(reader: nil, writer: nil, stderr: nil, wait_thread: nil, name: "test")

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

  def test_push_diagnostics__related_information
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

      worker = Server::WorkerProcess.new(reader: nil, writer: nil, stderr: nil, wait_thread: nil, name: "test")

      master = Server::Master.new(
        project: project,
        reader: worker_reader,
        writer: worker_writer,
        launcher: WorkersLauncher.new(worker)
      )

      range = { start: { line: 0, character: 0 }, end: { line: 0, character: 3 } }
      diagnostic = {
        message: "Duplicated",
        range: range,
        relatedInformation: [
          { location: { uri: Steep::PathHelper.to_uri(current_dir + "sig/b.rbs").to_s, range: range }, message: "Another definition" }
        ]
      }

      # Removed if the client doesn't support it
      master.assign_initialize_params(DEFAULT_CLI_LSP_INITIALIZE_PARAMS)
      master.push_diagnostics(current_dir + "sig/a.rbs", [diagnostic])
      flush_queue(master.write_queue).tap do |jobs|
        assert_equal [{ message: "Duplicated", range: range }], jobs.map { _1.message[:params][:diagnostics] }.flatten
      end

      # Kept if the client supports it
      master.assign_initialize_params(
        DEFAULT_CLI_LSP_INITIALIZE_PARAMS.merge(capabilities: { textDocument: { publishDiagnostics: { relatedInformation: true } } })
      )
      master.push_diagnostics(current_dir + "sig/a.rbs", [diagnostic])
      flush_queue(master.write_queue).tap do |jobs|
        assert_equal [diagnostic], jobs.map { _1.message[:params][:diagnostics] }.flatten
      end
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

      worker = Server::WorkerProcess.new(reader: nil, writer: nil, stderr: nil, wait_thread: nil, name: "test")

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

      worker = Server::WorkerProcess.new(reader: nil, writer: nil, stderr: nil, wait_thread: nil, name: "test")

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

      worker = Server::WorkerProcess.new(reader: nil, writer: nil, stderr: nil, wait_thread: nil, name: "test")

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

      worker1 = Server::WorkerProcess.new(reader: nil, writer: nil, stderr: nil, wait_thread: nil, name: "test-1")
      worker2 = Server::WorkerProcess.new(reader: nil, writer: nil, stderr: nil, wait_thread: nil, name: "test-2")

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

      worker = Server::WorkerProcess.new(reader: nil, writer: nil, stderr: nil, wait_thread: nil, name: "test")

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

      worker = Server::WorkerProcess.new(reader: nil, writer: nil, stderr: nil, wait_thread: nil, name: "test")

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

  def test_forked_workers_type_check
    skip "The platform cannot fork" unless Steep.can_fork?

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
      (current_dir + "lib/foo.rb").write("Foo.new.bar\n")
      (current_dir + "sig/foo.rbs").write("class Foo\nend\n")

      project = Project.new(steepfile_path: steepfile)
      Project::DSL.parse(project, steepfile.read)

      launcher = Server::ForkLauncher.new(typecheck_count: 2)

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
        # The workers have `Foo` in the environments forked from the master
        ui.open_file(project.absolute_path(Pathname("lib/foo.rb")))

        finally_holds do
          assert_equal(
            ["Ruby::NoMethod"],
            ui.diagnostics_for(project.absolute_path(Pathname("lib/foo.rb")))&.map { _1[:code] }
          )
        end

        first_generation = launcher.typecheck_workers.dup
        assert_equal 2, first_generation.size

        # The workers are forked again from the environments with the changed RBS file
        ui.open_file(project.absolute_path(Pathname("sig/foo.rbs")))
        ui.edit_file(project.absolute_path(Pathname("sig/foo.rbs")), content: <<-RBS, version: 0)
class Foo
  def bar: () -> void
end
        RBS
        ui.save_file(project.absolute_path(Pathname("sig/foo.rbs")))

        finally_holds do
          assert_equal [], ui.diagnostics_for(project.absolute_path(Pathname("lib/foo.rb")))
        end

        # The retired workers exit, and their pipes are closed
        finally_holds do
          assert_equal 2, launcher.typecheck_workers.size
          assert_empty launcher.typecheck_workers & first_generation
          assert first_generation.none? { _1.wait_thread.alive? }
          assert_empty launcher.retired_workers
          assert first_generation.all? { _1.writer.io.closed? }
        end
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

  def test_workspace_symbol_from_database
    in_tmpdir do
      steepfile = current_dir + "Steepfile"
      steepfile.write(<<-EOF)
target :lib do
  check "lib"
  signature "sig/lib"
end

target :test do
  check "test"
  signature "sig/test"
end
      EOF

      project = Project.new(steepfile_path: steepfile)
      Project::DSL.parse(project, steepfile.read)

      master = Server::Master.new(
        project: project,
        reader: worker_reader,
        writer: worker_writer,
        launcher: WorkersLauncher.new()
      )

      master.process_message_from_client({ id: "initialize", method: "initialize", params: DEFAULT_CLI_LSP_INITIALIZE_PARAMS })
      flush_queue(master.write_queue)

      # Nothing is found until the workers index the RBS files
      master.process_message_from_client({ id: "symbol-1", method: "workspace/symbol", params: { query: "Customer" } })
      response = flush_queue(master.write_queue).find { _1.message[:id] == "symbol-1" } or raise
      assert_empty response.message[:result]

      entry = -> (name, kind, line, start, finish, role: :definition) {
        Server::TypeCheckDatabase::Entry.new(name: name, role: role, kind: kind, start_line: line, start_character: start, end_line: line, end_character: finish)
      }
      path = Pathname("/gems/customer/customer.rbs")
      entries = [
        entry["::Customer", :class, 0, 6, 14],
        entry["::Customer#name", :attribute, 1, 14, 18],
        entry["::Customer.find", :method, 2, 11, 15],
        entry["::Customer::VERSION", :constant, 3, 2, 9],
        entry["::Customer::Address", :class, 5, 8, 15],
        entry["$customer", :global, 8, 0, 9],
        entry["::Customer", nil, 9, 11, 19, role: :reference]
      ]

      # A library RBS file indexed in the two targets
      master.type_check_database.update_rbs(path: path, target: :lib, entries: entries)
      master.type_check_database.update_rbs(path: path, target: :test, entries: entries)

      master.process_message_from_client({ id: "symbol-2", method: "workspace/symbol", params: { query: "customer" } })
      response = flush_queue(master.write_queue).find { _1.message[:id] == "symbol-2" } or raise
      symbols = response.message[:result]

      # Each declaration once, sorted by the name, without the reference
      assert_equal(
        [
          ["#name", LSP::Constant::SymbolKind::PROPERTY, "Customer"],
          ["$customer", LSP::Constant::SymbolKind::VARIABLE, nil],
          [".find", LSP::Constant::SymbolKind::METHOD, "Customer"],
          ["Address", LSP::Constant::SymbolKind::CLASS, "Customer"],
          ["Customer", LSP::Constant::SymbolKind::CLASS, ""],
          ["VERSION", LSP::Constant::SymbolKind::CONSTANT, "Customer"]
        ],
        symbols.map { [_1.name, _1.kind, _1.attributes[:containerName]] }
      )

      # The location is the name of the declaration
      customer = symbols.find { _1.name == "Customer" } or raise
      assert_equal PathHelper.to_uri(path).to_s, customer.location[:uri]
      assert_equal({ start: { line: 0, character: 6 }, end: { line: 0, character: 14 } }, customer.location[:range])

      # The query matches the fully qualified names
      master.process_message_from_client({ id: "symbol-3", method: "workspace/symbol", params: { query: "customer::" } })
      response = flush_queue(master.write_queue).find { _1.message[:id] == "symbol-3" } or raise
      assert_equal ["Address", "VERSION"], response.message[:result].map(&:name)
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

      worker = Server::WorkerProcess.new(reader: nil, writer: nil, stderr: nil, wait_thread: nil, name: "test")

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

      # Goto answers on the main loop
      run_environment_jobs(master)
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

      run_environment_jobs(master)
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

      worker = Server::WorkerProcess.new(reader: nil, writer: nil, stderr: nil, wait_thread: nil, name: "test")

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

  def test_index_on_initialize
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

      worker = Server::WorkerProcess.new(reader: nil, writer: nil, stderr: nil, wait_thread: nil, name: "test")

      master = Server::Master.new(
        project: project,
        reader: worker_reader,
        writer: worker_writer,
        launcher: WorkersLauncher.new(worker)
      )

      master.process_message_from_client({ id: "initialize", method: "initialize", params: DEFAULT_CLI_LSP_INITIALIZE_PARAMS })

      # The environment thread indexes the RBS files of the project in their targets, and every library RBS file in every target
      assert_empty flush_queue(master.write_queue).select { _1.message[:method] == TypeCheck__File::METHOD }
      assert_equal 2, master.environment_queue.size
      run_environment_jobs(master)

      database = master.type_check_database
      assert_equal [[current_dir + "sig/customer.rbs", :rbs, 0]], database.definitions("::Customer").map { [_1.path, _1.source, _1.start_line] }
      refute database.checked?(current_dir + "sig/customer.rbs")

      assert_includes database.definitions("::String").map(&:path), RBS::EnvironmentLoader::DEFAULT_CORE_ROOT + "string.rbs"

      master.process_message_from_client({ id: "definition", method: Query__Definition::METHOD, params: { name: "::Customer" } })
      response = flush_queue(master.write_queue).find { _1.message[:id] == "definition" } or raise
      assert_equal "type_name", response.message[:result][:kind]
      assert_equal [PathHelper.to_uri(current_dir + "sig/customer.rbs").to_s], response.message[:result][:locations].map { _1[:uri] }
    end
  end

  def test_index_changed_signatures_after_type_check
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
      (current_dir + "sig/customer.rbs").write("class Customer\nend\n")
      (current_dir + "sig/account.rbs").write("class Account\nend\n")

      project = Project.new(steepfile_path: steepfile)
      Project::DSL.parse(project, steepfile.read)

      worker = Server::WorkerProcess.new(reader: nil, writer: nil, stderr: nil, wait_thread: nil, name: "test")

      master = Server::Master.new(
        project: project,
        reader: worker_reader,
        writer: worker_writer,
        launcher: WorkersLauncher.new(worker)
      )
      master.typecheck_automatically = false

      master.process_message_from_client({ id: "initialize", method: "initialize", params: DEFAULT_CLI_LSP_INITIALIZE_PARAMS })
      flush_queue(master.write_queue)
      run_environment_jobs(master)

      master.controller.push_file_change(current_dir + "sig/customer.rbs", "class Customer\n  def name: () -> String\nend\n")
      master.controller.push_file_change(current_dir + "sig/account.rbs", "class Account\n  def id: () -> Integer\nend\n")

      # The type check validates `sig/customer.rbs`, and the environment thread indexes both of the changed files
      master.process_message_from_client({
        id: "check",
        method: TypeCheck::METHOD,
        params: {
          library_paths: [],
          signature_paths: [["lib", (current_dir + "sig/customer.rbs").to_s]],
          code_paths: [["lib", (current_dir + "lib/customer.rb").to_s]],
          inline_paths: []
        }
      })

      jobs = flush_queue(master.write_queue).select { _1.message[:method] == TypeCheck__File::METHOD }
      assert_equal ["code", "signature"], jobs.map { _1.message[:params][:kind] }

      database = master.type_check_database
      assert_empty database.definitions("::Customer#name")

      run_environment_jobs(master)
      assert_equal [[current_dir + "sig/customer.rbs", 1]], database.definitions("::Customer#name").map { [_1.path, _1.start_line] }
      assert_equal [[current_dir + "sig/account.rbs", 1]], database.definitions("::Account#id").map { [_1.path, _1.start_line] }
      refute database.checked?(current_dir + "sig/account.rbs")
    end
  end

  def test_broadcast_file_contents
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

      workers = 2.times.map { Server::WorkerProcess.new(reader: nil, writer: nil, stderr: nil, wait_thread: nil, name: "test@#{_1}") }

      master = Server::Master.new(
        project: project,
        reader: worker_reader,
        writer: worker_writer,
        launcher: WorkersLauncher.new(*workers)
      )
      master.typecheck_automatically = false

      master.process_message_from_client({ id: "initialize", method: "initialize", params: DEFAULT_CLI_LSP_INITIALIZE_PARAMS })

      # Every worker receives the RBS files on `initialize`
      jobs = flush_queue(master.write_queue).select { _1.dest.is_a?(Server::WorkerProcess) }
      assert_equal workers, jobs.map(&:dest)
      assert_equal [FileLoad::METHOD], jobs.map { _1.message[:method] }.uniq
      assert_equal({ "sig/customer.rbs" => "class Customer\nend\n" }, jobs[0].message[:params][:content])
      run_environment_jobs(master)

      # The Ruby file goes to the worker with its request, and the RBS file is not sent again
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

      jobs = flush_queue(master.write_queue).select { _1.dest.is_a?(Server::WorkerProcess) }
      assert_equal [TypeCheck__File::METHOD, TypeCheck__File::METHOD], jobs.map { _1.message[:method] }
      assert_equal "code", jobs[0].message[:params][:kind]
      assert_equal "class Customer\nend\n", jobs[0].message[:params][:content]
      assert_equal "signature", jobs[1].message[:params][:kind]
      refute_operator jobs[1].message[:params], :key?, :content

      jobs.each do |job|
        master.result_controller.process_response({ id: job.message[:id], result: { source: nil, signature: nil } })
      end
      flush_queue(master.write_queue)

      # A changed RBS file goes to every worker before the jobs, and the Ruby files go with their requests, changed or not
      master.process_message_from_client(
        {
          method: "textDocument/didChange",
          params: {
            textDocument: { uri: "#{file_scheme}#{current_dir + "lib/customer.rb"}" },
            contentChanges: [{ text: "class Customer\n  def name = \"\"\nend\n" }]
          }
        }
      )
      master.process_message_from_client(
        {
          method: "textDocument/didChange",
          params: {
            textDocument: { uri: "#{file_scheme}#{current_dir + "sig/customer.rbs"}" },
            contentChanges: [{ text: "class Customer\n  def name: () -> String\nend\n" }]
          }
        }
      )
      master.process_message_from_client({
        id: "check-2",
        method: TypeCheck::METHOD,
        params: {
          library_paths: [],
          signature_paths: [],
          code_paths: [["lib", (current_dir + "lib/customer.rb").to_s], ["lib", (current_dir + "lib/account.rb").to_s]],
          inline_paths: []
        }
      })

      jobs = flush_queue(master.write_queue).select { _1.dest.is_a?(Server::WorkerProcess) }
      assert_equal(
        [
          [workers[0], FileLoad::METHOD, { "sig/customer.rbs" => "class Customer\n  def name: () -> String\nend\n" }],
          [workers[1], FileLoad::METHOD, { "sig/customer.rbs" => "class Customer\n  def name: () -> String\nend\n" }],
          [workers[0], TypeCheck__File::METHOD, "class Customer\n  def name = \"\"\nend\n"],
          [workers[1], TypeCheck__File::METHOD, "class Account\nend\n"]
        ],
        jobs.map { |job| [job.dest, job.message[:method], job.message[:params][:content]] }
      )
      jobs.each do |job|
        master.result_controller.process_response({ id: job.message[:id], result: { source: nil, signature: nil } }) if job.message[:id]
      end
      flush_queue(master.write_queue)
      run_environment_jobs(master)

      # A change that leaves the declarations as they are is not sent: the master validates the file itself
      master.process_message_from_client(
        {
          method: "textDocument/didChange",
          params: {
            textDocument: { uri: "#{file_scheme}#{current_dir + "sig/customer.rbs"}" },
            contentChanges: [{ text: "# The customer\nclass Customer\n  def name: () -> String\nend\n" }]
          }
        }
      )
      master.process_message_from_client({
        id: "check-3",
        method: TypeCheck::METHOD,
        params: {
          library_paths: [],
          signature_paths: [["lib", (current_dir + "sig/customer.rbs").to_s]],
          code_paths: [],
          inline_paths: []
        }
      })

      assert_empty flush_queue(master.write_queue).select { _1.dest.is_a?(Server::WorkerProcess) }
      assert_equal Set[current_dir + "sig/customer.rbs"], master.signature_paths_to_validate
      refute_nil master.current_type_check_request

      run_environment_jobs(master)
      assert_nil master.current_type_check_request
      assert_equal [], master.type_check_database.diagnostics(current_dir + "sig/customer.rbs")
      assert_equal [[current_dir + "sig/customer.rbs", 1]], master.type_check_database.definitions("::Customer").map { [_1.path, _1.start_line] }

      # The next change of the declarations goes to the workers, which validate the file again
      master.process_message_from_client(
        {
          method: "textDocument/didChange",
          params: {
            textDocument: { uri: "#{file_scheme}#{current_dir + "sig/customer.rbs"}" },
            contentChanges: [{ text: "# The customer\nclass Customer\n  def name: () -> String\n  def id: () -> Integer\nend\n" }]
          }
        }
      )
      master.process_message_from_client({
        id: "check-4",
        method: TypeCheck::METHOD,
        params: {
          library_paths: [],
          signature_paths: [["lib", (current_dir + "sig/customer.rbs").to_s]],
          code_paths: [],
          inline_paths: []
        }
      })

      jobs = flush_queue(master.write_queue).select { _1.dest.is_a?(Server::WorkerProcess) }
      assert_equal [FileLoad::METHOD, FileLoad::METHOD, TypeCheck__File::METHOD], jobs.map { _1.message[:method] }
      assert_equal "signature", jobs[2].message[:params][:kind]
      assert_empty master.signature_paths_to_validate
    end
  end
end
