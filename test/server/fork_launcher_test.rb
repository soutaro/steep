require_relative "../test_helper"

class Steep::Server::ForkLauncherTest < Minitest::Test
  include TestHelper
  include ShellHelper

  include Steep

  def dirs
    @dirs ||= []
  end

  # Reads the messages from the worker until the response of the request
  #
  # @rbs (Steep::Server::WorkerProcess, String) -> untyped
  def read_response(worker, id)
    worker.read do |message|
      return message if message[:id] == id
    end
  end

  def test_create
    assert_instance_of Server::SpawnLauncher, Server::WorkerLauncher.create(steepfile: nil, steep_command: "steep", typecheck_count: 1)

    if Steep.can_fork?
      assert_instance_of Server::ForkLauncher, Server::WorkerLauncher.create(steepfile: nil, steep_command: nil, typecheck_count: 1)
    else
      assert_instance_of Server::SpawnLauncher, Server::WorkerLauncher.create(steepfile: nil, steep_command: nil, typecheck_count: 1)
    end
  end

  def test_workers_start_with_the_environments
    skip "The platform cannot fork" unless Steep.can_fork?

    in_tmpdir do
      steepfile = current_dir + "Steepfile"
      steepfile.write(<<~EOF)
        target :lib do
          check "lib"
          signature "sig"
        end
      EOF

      project = Project.new(steepfile_path: steepfile)
      Project::DSL.parse(project, steepfile.read)

      service = Services::TypeCheckService.new(project: project)
      service.update(changes: { Pathname("sig/customer.rbs") => [Services::ContentChange.string("class Customer\nend\n")] })

      launcher = Server::ForkLauncher.new(typecheck_count: 2)
      assert_predicate launcher, :shares_environment?
      assert_empty launcher.typecheck_workers

      begin
        launcher.start(service)
        assert_equal ["typecheck@0", "typecheck@1"], launcher.typecheck_workers.map(&:name)

        # The workers index the RBS file in the environments forked from the master, without receiving the content
        launcher.typecheck_workers.each do |worker|
          worker << Server::CustomMethods::TypeCheck__File.request(
            "index@#{worker.name}",
            { guid: "index", kind: "index", target: "lib", uri: PathHelper.to_uri(current_dir + "sig/customer.rbs").to_s }
          )

          response = read_response(worker, "index@#{worker.name}")
          assert_equal [["::Customer", 2, 0, 6, 0, 14]], response[:result][:signature][:entries]
        end
      ensure
        # The workers exit on `exit`
        launcher.typecheck_workers.each do |worker|
          worker << { method: "exit" }
          worker.wait_thread.join
        end
      end
    end
  end
end
