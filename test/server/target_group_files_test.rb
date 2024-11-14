require_relative "../test_helper"

class Steep::Server::TargetGroupFilesTest < Minitest::Test
  include TestHelper
  include ShellHelper
  include LSPTestHelper

  include Steep

  def default_project()
    project = Project.new(steepfile_path: Pathname("/app/Steepfile"))
    Project::DSL.eval(project) do
      target :lib do
        check "lib"
        signature "sig/lib"
      end

      target :app do
        group :server do
          check "app/server"
          signature "sig/app/server"
        end

        group :main do
          check "app/main"
          signature "sig/app/main"
        end

        check "app/cli.rb"
        signature "sig/app/cli.rbs"
      end

      target :test do
        unreferenced!

        check "test"
        signature "sig/test"
      end
    end
    project
  end

  def setup_files(files)
    files.project.targets.each do |target|
      files.add_library_path(target, Pathname("/rbs/core/object.rbs"))
      files.add_library_path(target, Pathname("/rbs/core/string.rbs"))
    end
    files.add_library_path(files.project.targets.find { _1.name == :test }, Pathname("/rbs/stdlib/test_unit.rbs"))

    files.add_path(Pathname("/app/lib/lib.rb"))
    files.add_path(Pathname("/app/app/server/server.rb"))
    files.add_path(Pathname("/app/app/main/main.rb"))
    files.add_path(Pathname("/app/app/cli.rb"))
    files.add_path(Pathname("/app/app/version.rb"))
    files.add_path(Pathname("/app/test/lib_test.rb"))

    files.add_path(Pathname("/app/sig/lib/lib.rbs"))
    files.add_path(Pathname("/app/sig/app/server/server.rbs"))
    files.add_path(Pathname("/app/sig/app/main/main.rbs"))
    files.add_path(Pathname("/app/sig/app/cli.rbs"))
    files.add_path(Pathname("/app/sig/test/lib_test.rbs"))
  end

  def test_files__each_library_path
    project = default_project()

    files = Server::TargetGroupFiles.new(project)
    setup_files(files)

    assert_equal Set[Pathname("/rbs/core/object.rbs"), Pathname("/rbs/core/string.rbs")], files.each_library_path(project.targets.find { _1.name == :lib }).to_set
    assert_equal Set[Pathname("/rbs/core/object.rbs"), Pathname("/rbs/core/string.rbs")], files.each_library_path(project.targets.find { _1.name == :app }).to_set
    assert_equal Set[Pathname("/rbs/core/object.rbs"), Pathname("/rbs/core/string.rbs"), Pathname("/rbs/stdlib/test_unit.rbs")], files.each_library_path(project.targets.find { _1.name == :test }).to_set
  end

  def test_files__each_group_signature_path__target
    project = default_project()

    files = Server::TargetGroupFiles.new(project)
    setup_files(files)

    project.targets.find { _1.name == :lib }.tap do |target|
      assert_equal Set[Pathname("/app/sig/lib/lib.rbs")], files.each_group_signature_path(target).to_set
    end
    project.targets.find { _1.name == :app }.tap do |target|
      assert_equal Set[Pathname("/app/sig/app/server/server.rbs"), Pathname("/app/sig/app/main/main.rbs"), Pathname("/app/sig/app/cli.rbs")], files.each_group_signature_path(target).to_set
    end
    project.targets.find { _1.name == :test }.tap do |target|
      assert_equal Set[Pathname("/app/sig/test/lib_test.rbs")], files.each_group_signature_path(target).to_set
    end
  end

  def test_files__each_group_source_path__target
    project = default_project()

    files = Server::TargetGroupFiles.new(project)
    setup_files(files)

    project.targets.find { _1.name == :lib }.tap do |target|
      assert_equal Set[Pathname("/app/lib/lib.rb")], files.each_group_source_path(target).to_set
    end
    project.targets.find { _1.name == :app }.tap do |target|
      assert_equal Set[Pathname("/app/app/server/server.rb"), Pathname("/app/app/main/main.rb"), Pathname("/app/app/cli.rb")], files.each_group_source_path(target).to_set
    end
    project.targets.find { _1.name == :test }.tap do |target|
      assert_equal Set[Pathname("/app/test/lib_test.rb")], files.each_group_source_path(target).to_set
    end
  end

  def test_files__each_group_signature_path__group
    project = default_project()

    files = Server::TargetGroupFiles.new(project)
    setup_files(files)

    project.targets.find { _1.name == :app }.tap do |target|
      target.groups.find { _1.name == :server }.tap do |group|
        assert_equal Set[Pathname("/app/sig/app/server/server.rbs")], files.each_group_signature_path(group).to_set
      end
      target.groups.find { _1.name == :main }.tap do |group|
        assert_equal Set[Pathname("/app/sig/app/main/main.rbs")], files.each_group_signature_path(group).to_set
      end
    end
  end

  def test_files__each_group_source_path__group
    project = default_project()

    files = Server::TargetGroupFiles.new(project)
    setup_files(files)

    project.targets.find { _1.name == :app }.tap do |target|
      target.groups.find { _1.name == :server }.tap do |group|
        assert_equal Set[Pathname("/app/app/server/server.rb")], files.each_group_source_path(group).to_set
      end
      target.groups.find { _1.name == :main }.tap do |group|
        assert_equal Set[Pathname("/app/app/main/main.rb")], files.each_group_source_path(group).to_set
      end
    end
  end

  def test_files__each_target_signature_path__no_group
    project = default_project()

    files = Server::TargetGroupFiles.new(project)
    setup_files(files)

    project.targets.find { _1.name == :lib }.tap do |target|
      assert_equal Set[Pathname("/app/sig/lib/lib.rbs")], files.each_target_signature_path(target, nil).to_set
    end
    project.targets.find { _1.name == :app }.tap do |target|
      assert_equal Set[Pathname("/app/sig/app/server/server.rbs"), Pathname("/app/sig/app/main/main.rbs"), Pathname("/app/sig/app/cli.rbs")], files.each_target_signature_path(target, nil).to_set
    end
    project.targets.find { _1.name == :test }.tap do |target|
      assert_equal Set[Pathname("/app/sig/test/lib_test.rbs")], files.each_target_signature_path(target, nil).to_set
    end
  end

  def test_files__each_target_source_path__no_group
    project = default_project()

    files = Server::TargetGroupFiles.new(project)
    setup_files(files)

    project.targets.find { _1.name == :lib }.tap do |target|
      assert_equal Set[Pathname("/app/lib/lib.rb")], files.each_target_source_path(target, nil).to_set
    end
    project.targets.find { _1.name == :app }.tap do |target|
      assert_equal Set[Pathname("/app/app/server/server.rb"), Pathname("/app/app/main/main.rb"), Pathname("/app/app/cli.rb")], files.each_target_source_path(target, nil).to_set
    end
    project.targets.find { _1.name == :test }.tap do |target|
      assert_equal Set[Pathname("/app/test/lib_test.rb")], files.each_target_source_path(target, nil).to_set
    end
  end

  def test_files__each_target_signature_path__group
    project = default_project()

    files = Server::TargetGroupFiles.new(project)
    setup_files(files)

    project.targets.find { _1.name == :app }.tap do |target|
      target.groups.find { _1.name == :server }.tap do |group|
        assert_equal Set[Pathname("/app/sig/app/main/main.rbs"), Pathname("/app/sig/app/cli.rbs")], files.each_target_signature_path(target, group).to_set
      end
      target.groups.find { _1.name == :main }.tap do |group|
        assert_equal Set[Pathname("/app/sig/app/server/server.rbs"), Pathname("/app/sig/app/cli.rbs")], files.each_target_signature_path(target, group).to_set
      end
    end
  end

  def test_files__each_target_source_path__group
    project = default_project()

    files = Server::TargetGroupFiles.new(project)
    setup_files(files)

    project.targets.find { _1.name == :app }.tap do |target|
      target.groups.find { _1.name == :server }.tap do |group|
        assert_equal Set[Pathname("/app/app/main/main.rb"), Pathname("/app/app/cli.rb")], files.each_target_source_path(target, group).to_set
      end
      target.groups.find { _1.name == :main }.tap do |group|
        assert_equal Set[Pathname("/app/app/server/server.rb"), Pathname("/app/app/cli.rb")], files.each_target_source_path(target, group).to_set
      end
    end
  end

  def test_files__each_project_signature_path__all_target
    project = default_project()

    files = Server::TargetGroupFiles.new(project)
    setup_files(files)

    assert_equal(
      Set[
        Pathname("/app/sig/lib/lib.rbs"),
        Pathname("/app/sig/app/server/server.rbs"), Pathname("/app/sig/app/main/main.rbs"), Pathname("/app/sig/app/cli.rbs"),
        Pathname("/app/sig/test/lib_test.rbs")
      ],
      files.each_project_signature_path(nil).to_set
    )
  end

  def test_files__each_project_source_path__all_target
    project = default_project()

    files = Server::TargetGroupFiles.new(project)
    setup_files(files)

    assert_equal(
      Set[
        Pathname("/app/lib/lib.rb"),
        Pathname("/app/app/server/server.rb"), Pathname("/app/app/main/main.rb"), Pathname("/app/app/cli.rb"),
        Pathname("/app/test/lib_test.rb")
      ],
      files.each_project_source_path(nil).to_set
    )
  end

  def test_files__each_project_signature_path__except_target
    project = default_project()

    files = Server::TargetGroupFiles.new(project)
    setup_files(files)

    project.targets.find { _1.name == :lib }.tap do |target|
      assert_equal(
        Set[
          Pathname("/app/sig/app/server/server.rbs"), Pathname("/app/sig/app/main/main.rbs"), Pathname("/app/sig/app/cli.rbs")
        ],
        files.each_project_signature_path(target).to_set
      )
    end

    project.targets.find { _1.name == :app }.tap do |target|
      assert_equal(
        Set[
          Pathname("/app/sig/lib/lib.rbs")
        ],
        files.each_project_signature_path(target).to_set
      )
    end

    project.targets.find { _1.name == :test }.tap do |target|
      assert_equal(
        Set[
          Pathname("/app/sig/lib/lib.rbs"),
          Pathname("/app/sig/app/server/server.rbs"), Pathname("/app/sig/app/main/main.rbs"), Pathname("/app/sig/app/cli.rbs")
        ],
        files.each_project_signature_path(target).to_set
      )
    end
  end

  def test_files__each_project_source_path__except_target
    project = default_project()

    files = Server::TargetGroupFiles.new(project)
    setup_files(files)

    project.targets.find { _1.name == :lib }.tap do |target|
      assert_equal(
        Set[
          Pathname("/app/app/server/server.rb"), Pathname("/app/app/main/main.rb"), Pathname("/app/app/cli.rb")
        ],
        files.each_project_source_path(target).to_set
      )
    end

    project.targets.find { _1.name == :app }.tap do |target|
      assert_equal(
        Set[
          Pathname("/app/lib/lib.rb")
        ],
        files.each_project_source_path(target).to_set
      )
    end

    project.targets.find { _1.name == :test }.tap do |target|
      assert_equal(
        Set[
          Pathname("/app/lib/lib.rb"),
          Pathname("/app/app/server/server.rb"), Pathname("/app/app/main/main.rb"), Pathname("/app/app/cli.rb")
        ],
        files.each_project_source_path(target).to_set
      )
    end
  end
end
