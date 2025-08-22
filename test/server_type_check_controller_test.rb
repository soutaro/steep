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
      assert_empty controller.open_paths
      assert_empty controller.new_active_groups
      assert_empty controller.active_groups
      assert_empty controller.dirty_code_paths
      assert_empty controller.dirty_signature_paths
      assert_empty controller.dirty_inline_paths

      assert_predicate controller.files.library_paths, :empty?
      assert_predicate controller.files.source_paths, :empty?
      assert_predicate controller.files.signature_paths, :empty?
      assert_predicate controller.files.inline_paths, :empty?
    end
  end

  def test_load
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.eval(project) do
        target :lib do
          check "lib"
          signature "sig"
          check "app", inline: true
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

      (current_dir + "app").mkdir
      (current_dir + "app/app.rb").write(<<-RBS)
class App
end
      RBS

      controller = Server::TypeCheckController.new(project: project)
      controller.load(command_line_args: []) {}

      assert_equal [:lib], controller.files.library_paths.keys
      assert_equal Set[current_dir + "lib/customer.rb"], controller.files.source_paths.paths.to_set
      assert_equal Set[current_dir + "sig/customer.rbs"], controller.files.signature_paths.paths.to_set
      assert_equal Set[current_dir + "app/app.rb"], controller.files.inline_paths.paths.to_set
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

  def test_add_dirty_path
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.eval(project) do
        target :lib do
          check "lib"
          signature "sig"
          check "app", inline: true
        end
      end

      controller = Server::TypeCheckController.new(project: project)
      controller.load(command_line_args: []) {}
      controller.reset

      controller.add_dirty_code_path(current_dir + "lib/customer.rb")
      controller.add_dirty_signature_path(current_dir + "sig/customer.rbs")
      controller.add_dirty_inline_path(current_dir + "app/app.rb", "")
      controller.add_dirty_code_path(current_dir + "test/customer_test.rb")

      assert_equal Set[current_dir + "lib/customer.rb"], controller.files.source_paths.paths.to_set
      assert_equal Set[current_dir + "sig/customer.rbs"], controller.files.signature_paths.paths.to_set
      assert_equal Set[current_dir + "app/app.rb"], controller.files.inline_paths.paths.to_set

      assert_equal Set[current_dir + "lib/customer.rb"], controller.dirty_code_paths
      assert_equal Set[current_dir + "sig/customer.rbs"], controller.dirty_signature_paths
      assert_equal Set[current_dir + "app/app.rb"], controller.dirty_inline_paths
    end
  end

  def test_open_path
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.eval(project) do
        target :lib do
          group :core do
            check "lib"
            signature "sig"
          end

          group :app do
            check "app", inline: true
          end
        end
      end

      controller = Server::TypeCheckController.new(project: project)
      controller.load(command_line_args: []) {}

      controller.open_path(current_dir + "lib/customer.rb")

      assert_equal Set[current_dir + "lib/customer.rb"], controller.open_paths
      assert_equal Set[:core], controller.active_groups.map(&:name).to_set
      assert_equal Set[:core], controller.new_active_groups.map(&:name).to_set

      controller.reset()

      controller.open_path(current_dir + "sig/customer.rbs")
      assert_equal Set[current_dir + "lib/customer.rb", current_dir + "sig/customer.rbs"], controller.open_paths
      assert_equal Set[:core], controller.active_groups.map(&:name).to_set
      assert_equal Set[], controller.new_active_groups.map(&:name).to_set
    end
  end

  def test_close_path
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.eval(project) do
        target :lib do
          group :core do
            check "lib"
            signature "sig"
          end

          group :app do
            check "app", inline: true
          end
        end
      end

      controller = Server::TypeCheckController.new(project: project)
      controller.load(command_line_args: []) {}

      controller.open_path(current_dir + "lib/customer.rb")
      controller.open_path(current_dir + "sig/customer.rbs")

      controller.close_path(current_dir + "lib/customer.rb")

      assert_equal Set[current_dir + "sig/customer.rbs"], controller.open_paths
      assert_equal Set[:core], controller.active_groups.map(&:name).to_set
      assert_equal Set[:core], controller.new_active_groups.map(&:name).to_set

      controller.close_path(current_dir + "sig/customer.rbs")

      assert_equal Set[], controller.open_paths
      assert_equal Set[], controller.active_groups.map(&:name).to_set
      assert_equal Set[], controller.new_active_groups.map(&:name).to_set
    end
  end

  def test_make_request_empty
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.eval(project) do
        target :lib do
          check "lib"
          signature "sig"
          check "app", inline: true
        end
      end

      controller = Server::TypeCheckController.new(project: project)
      controller.load(command_line_args: []) {}

      assert_nil controller.make_request(progress: WorkDoneProgress.new("guid") {})
    end
  end

  def test_make_all_request
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.eval(project) do
        target :app do
          group :core do
            check "lib/core"
            signature "sig/core"
          end

          group :app do
            check "lib/app", inline: true
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

      controller.files.add_path(current_dir + "test/customer_test.rb")
      controller.files.add_path(current_dir + "test/account_test.rb")
      controller.files.add_path(current_dir + "sig/test/customer_test.rbs")
      controller.files.add_path(current_dir + "sig/test/account_test.rbs")

      request = controller.make_all_request(progress: nil)

      assert_equal Set[], request.library_paths
      assert_equal Set[
        [:app, current_dir + "sig/core/customer.rbs"], [:app, current_dir + "sig/core/account.rbs"],
        [:test, current_dir + "sig/test/customer_test.rbs"], [:test, current_dir + "sig/test/account_test.rbs"]
      ], request.signature_paths
      assert_equal Set[
        [:app, current_dir + "lib/core/customer.rb"], [:app, current_dir + "lib/core/account.rb"],
        [:test, current_dir + "test/customer_test.rb"], [:test, current_dir + "test/account_test.rb"]
      ], request.code_paths
      assert_equal Set[
        [:app, current_dir + "lib/app/customer_service.rb"], [:app, current_dir + "lib/app/account_service.rb"],
      ], request.inline_paths
    end
  end

  def test_make_request__update_code
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.eval(project) do
        target :app do
          group :core do
            check "lib/core"
            signature "sig/core"
          end

          group :frontend do
            check "lib/app", inline: true
          end
        end

        target :test do
          unreferenced!
          check "test"
          signature "sig/test"
        end
      end

      controller = Server::TypeCheckController.new(project: project)

      controller.open_path(current_dir + "lib/core/customer.rb")
      controller.open_path(current_dir + "sig/core/customer.rbs")
      controller.open_path(current_dir + "test/customer_test.rb")
      controller.open_path(current_dir + "sig/test/customer_test.rbs")

      controller.make_request(progress: nil).tap do |request|
        request or raise

        assert_equal Set[], request.library_paths
        assert_equal Set[[:app, current_dir + "sig/core/customer.rbs"], [:test, current_dir + "sig/test/customer_test.rbs"]], request.signature_paths
        assert_equal Set[[:app, current_dir + "lib/core/customer.rb"], [:test, current_dir + "test/customer_test.rb"]], request.code_paths
        assert_equal Set[], request.inline_paths
      end

      # Edit the Ruby code
      controller.add_dirty_code_path(current_dir + "lib/core/customer.rb")

      controller.make_request(progress: nil).tap do |request|
        request or raise

        assert_equal Set[], request.library_paths
        assert_equal Set[], request.signature_paths
        assert_equal Set[[:app, current_dir + "lib/core/customer.rb"]], request.code_paths
        assert_equal Set[], request.inline_paths
      end

      # Edit the Ruby code (2)
      controller.add_dirty_code_path(current_dir + "test/customer_test.rb")

      controller.make_request(progress: nil).tap do |request|
        request or raise

        assert_equal Set[], request.library_paths
        assert_equal Set[], request.signature_paths
        assert_equal Set[[:test, current_dir + "test/customer_test.rb"]], request.code_paths
        assert_equal Set[], request.inline_paths
      end
    end
  end

  def test_make_request__update_signature
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.eval(project) do
        target :app do
          group :core do
            check "lib/core"
            signature "sig/core"
          end

          group :frontend do
            check "lib/app", inline: true
          end
        end

        target :test do
          unreferenced!
          check "test"
          signature "sig/test"
        end
      end

      controller = Server::TypeCheckController.new(project: project)

      controller.open_path(current_dir + "lib/core/customer.rb")
      controller.open_path(current_dir + "sig/core/customer.rbs")
      controller.open_path(current_dir + "test/customer_test.rb")
      controller.open_path(current_dir + "sig/test/customer_test.rbs")

      controller.make_request(progress: nil)

      # Edit the RBS in lib target
      controller.add_dirty_signature_path(current_dir + "sig/core/customer.rbs")

      controller.make_request(progress: nil).tap do |request|
        request or raise

        assert_equal Set[], request.library_paths
        assert_equal Set[[:app, current_dir + "sig/core/customer.rbs"], [:test, current_dir + "sig/test/customer_test.rbs"]], request.signature_paths
        assert_equal Set[[:app, current_dir + "lib/core/customer.rb"], [:test, current_dir + "test/customer_test.rb"]], request.code_paths
        assert_equal Set[], request.inline_paths
      end

      # Edit the RBS in test target
      controller.add_dirty_signature_path(current_dir + "sig/test/customer_test.rbs")

      controller.make_request(progress: nil).tap do |request|
        request or raise

        assert_equal Set[], request.library_paths
        assert_equal Set[[:test, current_dir + "sig/test/customer_test.rbs"]], request.signature_paths
        assert_equal Set[[:test, current_dir + "test/customer_test.rb"]], request.code_paths
        assert_equal Set[], request.inline_paths
      end
    end
  end

  def test_make_request__inline
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.eval(project) do
        target :app do
          group :frontend do
            check "lib/app", inline: true
          end
        end

        target :test do
          unreferenced!
          check "test"
          signature "sig/test"
        end
      end

      controller = Server::TypeCheckController.new(project: project)

      controller.open_path(current_dir + "test/customer_test.rb")
      controller.open_path(current_dir + "sig/test/customer_test.rbs")
      controller.open_inline_path(current_dir + "lib/app/customer.rb", <<-RUBY)
class Customer
  def initialize
  end
end
      RUBY

      controller.make_request(progress: nil).tap do |request|
        request or raise

        assert_equal Set[], request.library_paths
        assert_equal Set[[:test, current_dir + "sig/test/customer_test.rbs"]], request.signature_paths
        assert_equal Set[[:test, current_dir + "test/customer_test.rb"]], request.code_paths
        assert_equal Set[[:app, current_dir + "lib/app/customer.rb"]], request.inline_paths
      end

      # Edit the implementation of the inline Ruby code
      controller.add_dirty_inline_path(current_dir + "lib/app/customer.rb", <<-RUBY)
class Customer
  def initialize
    @name = "Alice"
  end
end
      RUBY

      controller.make_request(progress: nil).tap do |request|
        request or raise

        assert_equal Set[], request.library_paths
        assert_equal Set[], request.signature_paths
        assert_equal Set[], request.code_paths
        assert_equal Set[[:app, current_dir + "lib/app/customer.rb"]], request.inline_paths
      end

      # Edit the type declaration of the inline Ruby code
      controller.add_dirty_inline_path(current_dir + "lib/app/customer.rb", <<-RUBY)
class Customer
  def initialize
    @name = "Alice"
  end

  def to_s
    "Customer: \#{@name}"
  end
end
      RUBY

      controller.make_request(progress: nil).tap do |request|
        request or raise

        assert_equal Set[], request.library_paths
        assert_equal Set[[:test, current_dir + "sig/test/customer_test.rbs"]], request.signature_paths
        assert_equal Set[[:test, current_dir + "test/customer_test.rb"]], request.code_paths
        assert_equal Set[[:app, current_dir + "lib/app/customer.rb"]], request.inline_paths
      end
    end
  end

  def test_make_request__active_targets
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.eval(project) do
        target :app do
          group :frontend do
            check "lib/app", inline: true
          end
        end

        target :test do
          unreferenced!
          check "test"
          signature "sig/test"
        end
      end

      controller = Server::TypeCheckController.new(project: project)

      controller.open_path(current_dir + "test/customer_test.rb")
      controller.open_path(current_dir + "sig/test/customer_test.rbs")

      controller.make_request(progress: nil)

      # Edit test file, open targets are :test
      controller.add_dirty_signature_path(current_dir + "sig/test/customer_test.rbs")

      controller.make_request(progress: nil).tap do |request|
        request or raise

        assert_equal Set[], request.library_paths
        assert_equal Set[[:test, current_dir + "sig/test/customer_test.rbs"]], request.signature_paths
        assert_equal Set[[:test, current_dir + "test/customer_test.rb"]], request.code_paths
        assert_equal Set[], request.inline_paths
      end

      # Open :app file, open targets are :app, :test
      controller.open_path(current_dir + "lib/app/customer.rb")

      controller.make_request(progress: nil).tap do |request|
        request or raise

        assert_equal Set[], request.library_paths
        assert_equal Set[], request.signature_paths
        assert_equal Set[], request.code_paths
        assert_equal Set[[:app, current_dir + "lib/app/customer.rb"]], request.inline_paths
      end
    end
  end

  def test_make_group_request
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")
      Project::DSL.eval(project) do
        target :app do
          group :core do
            check "lib/core"
            signature "sig/core"
          end

          group :frontend do
            check "lib/app", inline: true
          end
        end

        target :test do
          unreferenced!
          check "test"
          signature "sig/test"
        end
      end

      controller = Server::TypeCheckController.new(project: project)

      controller.files.add_path(current_dir + "lib/core/customer.rb")
      controller.files.add_path(current_dir + "lib/core/account.rb")
      controller.files.add_path(current_dir + "sig/core/customer.rbs")
      controller.files.add_path(current_dir + "sig/core/account.rbs")

      controller.files.add_path(current_dir + "lib/app/customer_service.rb")
      controller.files.add_path(current_dir + "lib/app/account_service.rb")

      controller.files.add_path(current_dir + "test/customer_test.rb")
      controller.files.add_path(current_dir + "test/account_test.rb")
      controller.files.add_path(current_dir + "sig/test/customer_test.rbs")
      controller.files.add_path(current_dir + "sig/test/account_test.rbs")

      # Test requesting a single group
      request = controller.make_group_request(["app.core"], progress: WorkDoneProgress.new("guid") {})

      assert_equal Set[[:app, current_dir + "sig/core/customer.rbs"], [:app, current_dir + "sig/core/account.rbs"]], request.signature_paths
      assert_equal Set[[:app, current_dir + "lib/core/customer.rb"], [:app, current_dir + "lib/core/account.rb"]], request.code_paths
      assert_equal Set[], request.inline_paths
      assert_equal Set[], request.library_paths

      # Test requesting multiple groups
      request = controller.make_group_request(["app.core", "app.frontend"], progress: WorkDoneProgress.new("guid") {})

      assert_equal Set[[:app, current_dir + "sig/core/customer.rbs"], [:app, current_dir + "sig/core/account.rbs"]], request.signature_paths
      assert_equal Set[[:app, current_dir + "lib/core/customer.rb"], [:app, current_dir + "lib/core/account.rb"]], request.code_paths
      assert_equal Set[[:app, current_dir + "lib/app/customer_service.rb"], [:app, current_dir + "lib/app/account_service.rb"]], request.inline_paths
      assert_equal Set[], request.library_paths

      # Test requesting a target
      request = controller.make_group_request(["test"], progress: WorkDoneProgress.new("guid") {})

      assert_equal Set[[:test, current_dir + "sig/test/customer_test.rbs"], [:test, current_dir + "sig/test/account_test.rbs"]], request.signature_paths
      assert_equal Set[[:test, current_dir + "test/customer_test.rb"], [:test, current_dir + "test/account_test.rb"]], request.code_paths
      assert_equal Set[], request.inline_paths
      assert_equal Set[], request.library_paths

      # Test with open paths and dirty paths
      controller.open_path(current_dir + "lib/core/customer.rb")
      controller.open_path(current_dir + "lib/app/customer_service.rb")
      controller.add_dirty_signature_path(current_dir + "sig/core/customer.rbs")
      controller.add_dirty_inline_path(current_dir + "lib/app/customer_service.rb", "")

      request = controller.make_group_request(["app.core"], progress: WorkDoneProgress.new("guid") {})

      assert_equal Set[[:app, current_dir + "sig/core/customer.rbs"], [:app, current_dir + "sig/core/account.rbs"]], request.signature_paths
      assert_equal Set[[:app, current_dir + "lib/core/customer.rb"], [:app, current_dir + "lib/core/account.rb"]], request.code_paths
      assert_equal Set[], request.inline_paths

      # Should include open paths that belong to the requested groups
      assert_equal Set[current_dir + "lib/core/customer.rb", current_dir + "lib/app/customer_service.rb"], request.priority_paths

      # Verify dirty paths are removed for the requested group
      assert_equal Set[current_dir + "lib/app/customer_service.rb"], controller.each_dirty_path.to_set

      # Test that new_active_groups is updated
      # Close all paths first to reset active groups
      controller.close_path(current_dir + "lib/core/customer.rb")
      controller.close_path(current_dir + "lib/app/customer_service.rb")

      # Open a path to add its group to new_active_groups
      controller.open_path(current_dir + "lib/core/customer.rb")
      assert_equal 1, controller.new_active_groups.size
      assert_equal :core, controller.new_active_groups.first.name

      controller.make_group_request(["app.core"], progress: WorkDoneProgress.new("guid") {})
      assert_equal 0, controller.new_active_groups.size

      # Test with empty groups (should raise)
      assert_raises do
        controller.make_group_request([], progress: WorkDoneProgress.new("guid") {})
      end

      # Test with non-existent group (should raise)
      assert_raises do
        controller.make_group_request(["nonexistent"], progress: WorkDoneProgress.new("guid") {})
      end
    end
  end
end
