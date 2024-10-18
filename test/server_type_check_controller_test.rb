require_relative "test_helper"

class ServerTypeCheckControllerTest < Minitest::Test
  include TestHelper
  include ShellHelper
  include LSPTestHelper

  include Steep
  TypeCheckController = Server::TypeCheckController
  WorkDoneProgress = Server::WorkDoneProgress

  def dirs
    @dirs ||= []
  end

  def test_target_paths
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

      paths = TypeCheckController::TargetPaths.new(project: project, target: project.targets[0])

      (current_dir + "sig/customer.rbs").tap do |path|
        paths << path

        assert_equal Set[path], paths.signature_paths
        assert_operator paths, :signature_path?, path
      end

      (current_dir + "lib/customer.rb").tap do |path|
        paths << path

        assert_equal Set[path], paths.code_paths
        assert_operator paths, :code_path?, path
      end

      (RBS::EnvironmentLoader::DEFAULT_CORE_ROOT + "object.rbs").tap do |path|
        paths.add(path, library: true)

        assert_equal Set[path], paths.library_paths
        assert_operator paths, :library_path?, path
      end
    end
  end

  def test_initialize
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

      controller = Server::TypeCheckController.new(project: project)

      assert_equal project, controller.project
      assert_equal Set[], controller.priority_paths
      assert_equal Set[], controller.changed_paths

      assert_equal 1, controller.target_paths.size
      controller.target_paths[0].tap do |paths|
        assert_equal project.targets[0], paths.target
        assert_equal Set[], paths.code_paths
        assert_equal Set[], paths.signature_paths
        assert_equal Set[], paths.library_paths
      end
    end
  end

  def test_load
    in_tmpdir do
      steepfile = current_dir + "Steepfile"
      steepfile.write(<<-EOF)
target :lib do
  check "lib"
  signature "sig"
end
      EOF
      (current_dir + "lib").mkdir
      (current_dir + "lib/customer.rb").write(<<-RUBY)
class Customer
end
      RUBY

      (current_dir + "sig").mkdir
      (current_dir + "sig/customer.rbs").write(<<-RBS)
class Customer
end
      RBS

      project = Project.new(steepfile_path: steepfile)
      Project::DSL.parse(project, steepfile.read)

      controller = Server::TypeCheckController.new(project: project)
      controller.load(command_line_args: []) {}

      controller.target_paths[0].tap do |paths|
        assert_equal Set[current_dir + "lib/customer.rb"], paths.code_paths
        assert_equal Set[current_dir + "sig/customer.rbs"], paths.signature_paths
        assert_operator paths.library_paths, :include?, RBS::EnvironmentLoader::DEFAULT_CORE_ROOT + "object.rbs"
      end

      assert_equal controller.target_paths[0].all_paths, controller.changed_paths
    end
  end

  def test_push_changes_project_file
    in_tmpdir do
      steepfile = current_dir + "Steepfile"
      steepfile.write(<<-EOF)
target :lib do
  check "lib"
  signature "sig"
end
      EOF
      (current_dir + "lib").mkdir
      (current_dir + "lib/customer.rb").write(<<-RUBY)
class Customer
end
      RUBY

      (current_dir + "sig").mkdir

      project = Project.new(steepfile_path: steepfile)
      Project::DSL.parse(project, steepfile.read)

      controller = Server::TypeCheckController.new(project: project)
      controller.load(command_line_args: []) {}
      controller.changed_paths.clear()

      controller.push_changes(current_dir + "lib/customer.rb")
      controller.push_changes(current_dir + "sig/customer.rbs")
      controller.push_changes(current_dir + "test/customer_test.rb")

      controller.target_paths[0].tap do |paths|
        assert_equal Set[current_dir + "lib/customer.rb"],
                     paths.code_paths
        assert_equal Set[current_dir + "sig/customer.rbs"],
                     paths.signature_paths
      end

      assert_equal Set[current_dir + "lib/customer.rb", current_dir + "sig/customer.rbs"],
                   controller.changed_paths
    end
  end

  def test_update_priority
    in_tmpdir do
      steepfile = current_dir + "Steepfile"
      steepfile.write(<<-EOF)
target :lib do
  check "lib"
  signature "sig"
end
      EOF
      (current_dir + "lib").mkdir
      (current_dir + "lib/customer.rb").write(<<-RUBY)
class Customer
end
      RUBY

      (current_dir + "sig").mkdir

      project = Project.new(steepfile_path: steepfile)
      Project::DSL.parse(project, steepfile.read)

      controller = Server::TypeCheckController.new(project: project)
      controller.load(command_line_args: []) {}
      controller.changed_paths.clear()

      controller.update_priority(open: current_dir + "lib/customer.rb")
      controller.update_priority(open: current_dir + "sig/customer.rbs")

      assert_equal Set[current_dir + "lib/customer.rb", current_dir + "sig/customer.rbs"],
                   controller.priority_paths

      controller.target_paths[0].tap do |paths|
        assert_equal Set[current_dir + "sig/customer.rbs"], paths.signature_paths
      end
    end
  end

  def test_make_request_empty
    in_tmpdir do
      steepfile = current_dir + "Steepfile"
      steepfile.write(<<-EOF)
target :lib do
  check "lib"
  signature "sig"
end
      EOF
      (current_dir + "lib").mkdir
      (current_dir + "lib/customer.rb").write(<<-RUBY)
class Customer
end
      RUBY

      (current_dir + "sig").mkdir

      project = Project.new(steepfile_path: steepfile)
      Project::DSL.parse(project, steepfile.read)

      controller = Server::TypeCheckController.new(project: project)
      controller.load(command_line_args: []) {}
      controller.changed_paths.clear()

      assert_nil controller.make_request(progress: WorkDoneProgress.new("guid") {})
    end
  end

  def test_make_request_with_signature
    in_tmpdir do
      steepfile = current_dir + "Steepfile"
      steepfile.write(<<-EOF)
target :lib do
  check "lib"
  signature "sig"
end
      EOF
      (current_dir + "lib").mkdir
      (current_dir + "lib/customer.rb").write(<<-RUBY)
class Customer
end
      RUBY

      (current_dir + "sig").mkdir

      project = Project.new(steepfile_path: steepfile)
      Project::DSL.parse(project, steepfile.read)

      controller = Server::TypeCheckController.new(project: project)
      controller.load(command_line_args: []) {}
      controller.changed_paths.clear()

      controller.update_priority(open: current_dir + "lib/customer.rb")
      controller.push_changes(current_dir + "sig/customer.rbs")

      request = controller.make_request(progress: WorkDoneProgress.new("guid") {})
      assert_equal Set[[:lib, current_dir + "sig/customer.rbs"]], request.signature_paths
      assert_equal Set[[:lib, current_dir + "lib/customer.rb"]], request.code_paths
      assert_equal Set[current_dir + "lib/customer.rb"], request.priority_paths
      assert_operator request.library_paths.size, :>, 0

      assert_equal Set[], controller.changed_paths
    end
  end

  def test_make_request_with_code
    in_tmpdir do
      steepfile = current_dir + "Steepfile"
      steepfile.write(<<-EOF)
target :lib do
  check "lib"
  signature "sig"
end
      EOF
      (current_dir + "lib").mkdir
      (current_dir + "lib/customer.rb").write(<<-RUBY)
class Customer
end
      RUBY

      (current_dir + "sig").mkdir

      project = Project.new(steepfile_path: steepfile)
      Project::DSL.parse(project, steepfile.read)

      controller = Server::TypeCheckController.new(project: project)
      controller.load(command_line_args: []) {}
      controller.changed_paths.clear()

      controller.update_priority(open: current_dir + "lib/customer.rb")
      controller.push_changes(current_dir + "lib/customer.rb")

      request = controller.make_request(progress: WorkDoneProgress.new("guid") {})
      assert_equal Set[], request.signature_paths
      assert_equal Set[[:lib, current_dir + "lib/customer.rb"]], request.code_paths
      assert_equal Set[current_dir + "lib/customer.rb"], request.priority_paths
      assert_operator request.library_paths.size, :==, 0

      assert_equal Set[], controller.changed_paths
    end
  end

  def test_make_request_with_last_request
    in_tmpdir do
      steepfile = current_dir + "Steepfile"
      steepfile.write(<<-EOF)
target :lib do
  check "lib"
  signature "sig"
end
      EOF
      (current_dir + "lib").mkdir
      (current_dir + "lib/customer.rb").write(<<-RUBY)
class Customer
end
      RUBY
      (current_dir + "lib/account.rb").write(<<-RUBY)
class Account
end
      RUBY

      (current_dir + "sig").mkdir

      project = Project.new(steepfile_path: steepfile)
      Project::DSL.parse(project, steepfile.read)

      controller = Server::TypeCheckController.new(project: project)
      controller.load(command_line_args: []) {}
      controller.changed_paths.clear()

      controller.update_priority(open: current_dir + "lib/customer.rb")
      controller.push_changes(current_dir + "lib/customer.rb")

      last_request = Server::TypeCheckController::Request.new(guid: "last_guid", progress: WorkDoneProgress.new("guid") {})
      last_request.code_paths << [:lib, current_dir + "lib/account.rb"]
      last_request.signature_paths << [:lib, current_dir + "sig/account.rbs"]
      last_request.library_paths << [:lib, RBS::EnvironmentLoader::DEFAULT_CORE_ROOT + "integer.rbs"]

      request = controller.make_request(last_request: last_request, progress: WorkDoneProgress.new("guid") {})
      assert_equal Set[current_dir + "lib/customer.rb"], request.priority_paths
      assert_equal Set[[:lib, current_dir + "sig/account.rbs"]], request.signature_paths
      assert_equal Set[[:lib, current_dir + "lib/customer.rb"], [:lib, current_dir + "lib/account.rb"]], request.code_paths
      assert_equal Set[[:lib, RBS::EnvironmentLoader::DEFAULT_CORE_ROOT + "integer.rbs"]], request.library_paths

      assert_equal Set[], controller.changed_paths
    end
  end
end
