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

      assert_predicate controller.files.library_paths, :empty?
      assert_predicate controller.files.source_paths, :empty?
      assert_predicate controller.files.signature_paths, :empty?
    end
  end

  def test_load
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.eval(project) do
        target :lib do
          check "lib"
          signature "sig"
        end
      end

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

      controller = Server::TypeCheckController.new(project: project)
      controller.load(command_line_args: []) {}

      assert_equal [:lib], controller.files.library_paths.keys
      assert_equal Set[current_dir + "lib/customer.rb"], controller.files.source_paths.paths.to_set
      assert_equal Set[current_dir + "sig/customer.rbs"], controller.files.signature_paths.paths.to_set
    end
  end

  def test_load__groups
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.eval(project) do
        target :lib do
          group :core do
            check "lib/core.rb"
            signature "sig/core.rbs"
          end

          check "lib"
          signature "sig"
        end
      end

      (current_dir + "lib").mkdir
      (current_dir + "lib/customer.rb").write("")
      (current_dir + "lib/core.rb").write("")

      (current_dir + "sig").mkdir
      (current_dir + "sig/customer.rbs").write("")
      (current_dir + "sig/core.rbs").write("")

      controller = Server::TypeCheckController.new(project: project)
      controller.load(command_line_args: []) {}

      assert_equal [:lib], controller.files.library_paths.keys
      assert_equal Set[current_dir + "lib/customer.rb", current_dir + "lib/core.rb"], controller.files.source_paths.paths.to_set
      assert_equal Set[current_dir + "sig/customer.rbs", current_dir + "sig/core.rbs"], controller.files.signature_paths.paths.to_set
    end
  end

  def test_push_changes_project_file
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.eval(project) do
        target :lib do
          check "lib"
          signature "sig"
        end
      end

      (current_dir + "lib").mkdir
      (current_dir + "lib/customer.rb").write(<<-RUBY)
class Customer
end
      RUBY

      (current_dir + "sig").mkdir

      controller = Server::TypeCheckController.new(project: project)
      controller.load(command_line_args: []) {}
      controller.changed_paths.clear()

      controller.push_changes(current_dir + "lib/customer.rb")
      controller.push_changes(current_dir + "sig/customer.rbs")
      controller.push_changes(current_dir + "test/customer_test.rb")

      assert_equal Set[current_dir + "lib/customer.rb"], controller.files.source_paths.paths.to_set
      assert_equal Set[current_dir + "sig/customer.rbs"], controller.files.signature_paths.paths.to_set

      assert_equal Set[current_dir + "lib/customer.rb", current_dir + "sig/customer.rbs"],
                   controller.changed_paths
    end
  end

  def test_update_priority
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.eval(project) do
        target :lib do
          check "lib"
          signature "sig"
        end
      end

      (current_dir + "lib").mkdir
      (current_dir + "lib/customer.rb").write(<<-RUBY)
class Customer
end
      RUBY

      (current_dir + "sig").mkdir

      controller = Server::TypeCheckController.new(project: project)
      controller.load(command_line_args: []) {}
      controller.changed_paths.clear()

      controller.update_priority(open: current_dir + "lib/customer.rb")
      controller.update_priority(open: current_dir + "sig/customer.rbs")

      assert_equal Set[current_dir + "lib/customer.rb", current_dir + "sig/customer.rbs"],
                   controller.priority_paths
    end
  end

  def test_make_request_empty
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.eval(project) do
        target :lib do
          check "lib"
          signature "sig"
        end
      end

      (current_dir + "lib").mkdir
      (current_dir + "lib/customer.rb").write(<<-RUBY)
class Customer
end
      RUBY

      (current_dir + "sig").mkdir

      controller = Server::TypeCheckController.new(project: project)
      controller.load(command_line_args: []) {}
      controller.changed_paths.clear()

      assert_nil controller.make_request(progress: WorkDoneProgress.new("guid") {})
    end
  end

  def test_make_request__include_unchanged
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.eval(project) do
        target :app do
          group :core do
            check "lib/core"
            signature "sig/core"
          end

          group :app do
            check "lib/app"
            signature "sig/app"
          end
        end

        target :test do
          unreferenced!
          check "test"
          signature "sig/test"
        end
      end

      controller = Server::TypeCheckController.new(project: project)

      project.targets.each do |target|
        controller.files.add_library_path(target, Pathname("/rbs/core/object.rbs"), Pathname("/rbs/core/string.rbs"))
        if target.name == :test
          controller.files.add_library_path(target, Pathname("/rbs/core/test_unit.rbs"))
        end
      end

      controller.files.add_path(current_dir + "lib/core/customer.rb")
      controller.files.add_path(current_dir + "lib/core/account.rb")
      controller.files.add_path(current_dir + "sig/core/customer.rbs")
      controller.files.add_path(current_dir + "sig/core/account.rbs")

      controller.files.add_path(current_dir + "lib/app/customer_service.rb")
      controller.files.add_path(current_dir + "lib/app/account_service.rb")
      controller.files.add_path(current_dir + "sig/app/customer_service.rbs")
      controller.files.add_path(current_dir + "sig/app/account_service.rbs")

      controller.files.add_path(current_dir + "test/customer_test.rb")
      controller.files.add_path(current_dir + "test/account_test.rb")
      controller.files.add_path(current_dir + "sig/test/customer_test.rbs")
      controller.files.add_path(current_dir + "sig/test/account_test.rbs")

      request = controller.make_request(progress: nil, include_unchanged: true)

      assert_equal Set[], request.library_paths
      assert_equal Set[
        [:app, current_dir + "sig/core/customer.rbs"], [:app, current_dir + "sig/core/account.rbs"],
        [:app, current_dir + "sig/app/customer_service.rbs"], [:app, current_dir + "sig/app/account_service.rbs"],
        [:test, current_dir + "sig/test/customer_test.rbs"], [:test, current_dir + "sig/test/account_test.rbs"]
      ], request.signature_paths
      assert_equal Set[
        [:app, current_dir + "lib/core/customer.rb"], [:app, current_dir + "lib/core/account.rb"],
        [:app, current_dir + "lib/app/customer_service.rb"], [:app, current_dir + "lib/app/account_service.rb"],
        [:test, current_dir + "test/customer_test.rb"], [:test, current_dir + "test/account_test.rb"]
      ], request.code_paths
    end
  end

  def test_make_request__code_changed
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.eval(project) do
        target :app do
          group :core do
            check "lib/core"
            signature "sig/core"
          end

          group :app do
            check "lib/app"
            signature "sig/app"
          end
        end

        target :test do
          unreferenced!
          check "test"
          signature "sig/test"
        end
      end

      controller = Server::TypeCheckController.new(project: project)

      project.targets.each do |target|
        controller.files.add_library_path(target, Pathname("/rbs/core/object.rbs"), Pathname("/rbs/core/string.rbs"))
        if target.name == :test
          controller.files.add_library_path(target, Pathname("/rbs/core/test_unit.rbs"))
        end
      end

      controller.files.add_path(current_dir + "lib/core/customer.rb")
      controller.files.add_path(current_dir + "lib/core/account.rb")
      controller.files.add_path(current_dir + "sig/core/customer.rbs")
      controller.files.add_path(current_dir + "sig/core/account.rbs")

      controller.files.add_path(current_dir + "lib/app/customer_service.rb")
      controller.files.add_path(current_dir + "lib/app/account_service.rb")
      controller.files.add_path(current_dir + "sig/app/customer_service.rbs")
      controller.files.add_path(current_dir + "sig/app/account_service.rbs")

      controller.files.add_path(current_dir + "test/customer_test.rb")
      controller.files.add_path(current_dir + "test/account_test.rb")
      controller.files.add_path(current_dir + "sig/test/customer_test.rbs")
      controller.files.add_path(current_dir + "sig/test/account_test.rbs")

      controller.push_changes(current_dir + "lib/core/customer.rb")
      request = controller.make_request(progress: nil)

      assert_equal Set[], request.library_paths
      assert_equal Set[], request.signature_paths
      assert_equal Set[
        [:app, current_dir + "lib/core/customer.rb"],
      ], request.code_paths
    end
  end

  def test_make_request__signature_changed
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.eval(project) do
        target :app do
          group :core do
            check "lib/core"
            signature "sig/core"
          end

          group :app do
            check "lib/app"
            signature "sig/app"
          end
        end

        target :test do
          unreferenced!
          check "test"
          signature "sig/test"
        end
      end

      controller = Server::TypeCheckController.new(project: project)

      project.targets.each do |target|
        controller.files.add_library_path(target, Pathname("/rbs/core/object.rbs"), Pathname("/rbs/core/string.rbs"))
        if target.name == :test
          controller.files.add_library_path(target, Pathname("/rbs/core/test_unit.rbs"))
        end
      end

      controller.files.add_path(current_dir + "lib/core/customer.rb")
      controller.files.add_path(current_dir + "lib/core/account.rb")
      controller.files.add_path(current_dir + "sig/core/customer.rbs")
      controller.files.add_path(current_dir + "sig/core/account.rbs")

      controller.files.add_path(current_dir + "lib/app/customer_service.rb")
      controller.files.add_path(current_dir + "lib/app/account_service.rb")
      controller.files.add_path(current_dir + "sig/app/customer_service.rbs")
      controller.files.add_path(current_dir + "sig/app/account_service.rbs")

      controller.files.add_path(current_dir + "test/customer_test.rb")
      controller.files.add_path(current_dir + "test/account_test.rb")
      controller.files.add_path(current_dir + "sig/test/customer_test.rbs")
      controller.files.add_path(current_dir + "sig/test/account_test.rbs")

      controller.push_changes(current_dir + "sig/app/customer_service.rbs")
      request = controller.make_request(progress: nil)

      assert_equal Set[], request.library_paths
      assert_equal Set[
        [:app, current_dir + "sig/app/customer_service.rbs"], [:app, current_dir + "sig/app/account_service.rbs"],
      ], request.signature_paths
      assert_equal Set[
        [:app, current_dir + "lib/app/customer_service.rb"], [:app, current_dir + "lib/app/account_service.rb"],
      ], request.code_paths
    end
  end

  def test_make_request__other_group_priority
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.eval(project) do
        target :app do
          group :core do
            check "lib/core"
            signature "sig/core"
          end

          group :app do
            check "lib/app"
            signature "sig/app"
          end
        end

        target :test do
          unreferenced!
          check "test"
          signature "sig/test"
        end
      end

      controller = Server::TypeCheckController.new(project: project)

      project.targets.each do |target|
        controller.files.add_library_path(target, Pathname("/rbs/core/object.rbs"), Pathname("/rbs/core/string.rbs"))
        if target.name == :test
          controller.files.add_library_path(target, Pathname("/rbs/core/test_unit.rbs"))
        end
      end

      controller.files.add_path(current_dir + "lib/core/customer.rb")
      controller.files.add_path(current_dir + "lib/core/account.rb")
      controller.files.add_path(current_dir + "sig/core/customer.rbs")
      controller.files.add_path(current_dir + "sig/core/account.rbs")

      controller.files.add_path(current_dir + "lib/app/customer_service.rb")
      controller.files.add_path(current_dir + "lib/app/account_service.rb")
      controller.files.add_path(current_dir + "sig/app/customer_service.rbs")
      controller.files.add_path(current_dir + "sig/app/account_service.rbs")

      controller.files.add_path(current_dir + "test/customer_test.rb")
      controller.files.add_path(current_dir + "test/account_test.rb")
      controller.files.add_path(current_dir + "sig/test/customer_test.rbs")
      controller.files.add_path(current_dir + "sig/test/account_test.rbs")

      controller.update_priority(open: current_dir + "lib/app/customer_service.rb")
      controller.make_request(progress: nil)

      controller.push_changes(current_dir + "sig/core/customer.rbs")
      request = controller.make_request(progress: nil)

      assert_equal Set[], request.library_paths
      assert_equal Set[
        [:app, current_dir + "sig/core/customer.rbs"], [:app, current_dir + "sig/core/account.rbs"],
      ], request.signature_paths
      assert_equal Set[
        [:app, current_dir + "lib/core/customer.rb"], [:app, current_dir + "lib/core/account.rb"],
        [:app, current_dir + "lib/app/customer_service.rb"],
      ], request.code_paths
    end
  end

  def test_make_request__other_group_priority__unreferenced
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.eval(project) do
        target :app do
          group :core do
            check "lib/core"
            signature "sig/core"
          end

          group :app do
            check "lib/app"
            signature "sig/app"
          end
        end

        target :test do
          unreferenced!
          check "test"
          signature "sig/test"
        end
      end

      controller = Server::TypeCheckController.new(project: project)

      project.targets.each do |target|
        controller.files.add_library_path(target, Pathname("/rbs/core/object.rbs"), Pathname("/rbs/core/string.rbs"))
        if target.name == :test
          controller.files.add_library_path(target, Pathname("/rbs/core/test_unit.rbs"))
        end
      end

      controller.files.add_path(current_dir + "lib/core/customer.rb")
      controller.files.add_path(current_dir + "lib/core/account.rb")
      controller.files.add_path(current_dir + "sig/core/customer.rbs")
      controller.files.add_path(current_dir + "sig/core/account.rbs")

      controller.files.add_path(current_dir + "lib/app/customer_service.rb")
      controller.files.add_path(current_dir + "lib/app/account_service.rb")
      controller.files.add_path(current_dir + "sig/app/customer_service.rbs")
      controller.files.add_path(current_dir + "sig/app/account_service.rbs")

      controller.files.add_path(current_dir + "test/customer_test.rb")
      controller.files.add_path(current_dir + "test/account_test.rb")
      controller.files.add_path(current_dir + "sig/test/customer_test.rbs")
      controller.files.add_path(current_dir + "sig/test/account_test.rbs")

      controller.update_priority(open: current_dir + "lib/app/customer_service.rb")
      controller.make_request(progress: nil)

      controller.push_changes(current_dir + "sig/test/customer_test.rbs")
      request = controller.make_request(progress: nil)

      assert_equal Set[], request.library_paths
      assert_equal Set[
        [:test, current_dir + "sig/test/customer_test.rbs"], [:test, current_dir + "sig/test/account_test.rbs"],
      ], request.signature_paths
      assert_equal Set[
        [:test, current_dir + "test/customer_test.rb"], [:test, current_dir + "test/account_test.rb"],
      ], request.code_paths
    end
  end
end
