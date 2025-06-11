require_relative "../test_helper"

class Steep::Server::TargetGroupFilesTest < Minitest::Test
  include TestHelper
  include ShellHelper
  include LSPTestHelper

  include Steep

  def default_project() #: Steep::Project
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

        check "app/version.rb", inline: true
      end

      target :test do
        unreferenced!

        check "test"
        signature "sig/test"
      end
    end
    project
  end

  def test__add_path()
    files = Server::TargetGroupFiles.new(default_project())

    files.add_path(Pathname("/app/lib/lib.rb"))
    files.add_path(Pathname("/app/app/cli.rb"))
    files.add_path(Pathname("/app/test/lib_test.rb"))

    files.add_path(Pathname("/app/sig/lib/lib.rbs"))
    files.add_path(Pathname("/app/sig/app/cli.rbs"))
    files.add_path(Pathname("/app/sig/test/lib_test.rbs"))

    files.add_path(Pathname("/app/app/version.rb"))

    assert_equal(
      Set[
        Pathname("/app/lib/lib.rb"),
        Pathname("/app/app/cli.rb"),
        Pathname("/app/test/lib_test.rb")
      ],
      files.source_paths.paths.to_set
    )

    assert_equal(
      Set[
        Pathname("/app/sig/lib/lib.rbs"),
        Pathname("/app/sig/app/cli.rbs"),
        Pathname("/app/sig/test/lib_test.rbs")
      ],
      files.signature_paths.paths.to_set
    )

    assert_equal(
      Set[
        Pathname("/app/app/version.rb")
      ],
      files.inline_paths.paths.to_set
    )
  end

  def test__add_library_path
    project = default_project
    files = Server::TargetGroupFiles.new(project)

    files.project.targets.each do |target|
      files.add_library_path(target, Pathname("/rbs/core/object.rbs"))
      files.add_library_path(target, Pathname("/rbs/core/string.rbs"))
    end
    files.add_library_path(files.project.targets.find { _1.name == :test }, Pathname("/rbs/stdlib/test_unit.rbs"))

    assert_equal Set[Pathname("/rbs/core/object.rbs"), Pathname("/rbs/core/string.rbs")], files.each_library_path(project.targets.find { _1.name == :lib }).to_set
    assert_equal Set[Pathname("/rbs/core/object.rbs"), Pathname("/rbs/core/string.rbs")], files.each_library_path(project.targets.find { _1.name == :app }).to_set
    assert_equal Set[Pathname("/rbs/core/object.rbs"), Pathname("/rbs/core/string.rbs"), Pathname("/rbs/stdlib/test_unit.rbs")], files.each_library_path(project.targets.find { _1.name == :test }).to_set
  end

  # Returns a default enumerator with `.rb` files
  #
  def default_enumerator(project) #: Server::TargetGroupFiles::PathEnumerator
    enumerator = Server::TargetGroupFiles::PathEnumerator.new

    project.targets.find { _1.name == :lib }.tap do |target|
      target or raise
      enumerator[Pathname("/app/lib/lib.rb")] = target
    end

    project.targets.find { _1.name == :app }.tap do |target|
      target or raise

      target.groups.find { _1.name == :server }.tap do |group|
        group or raise
        enumerator[Pathname("/app/app/server/server.rb")] = group
      end

      target.groups.find { _1.name == :main }.tap do |group|
        group or raise
        enumerator[Pathname("/app/app/main/main.rb")] = group
      end

      enumerator[Pathname("/app/app/cli.rb")] = target
    end

    project.targets.find { _1.name == :test }.tap do |target|
      target or raise
      enumerator[Pathname("/app/test/lib_test.rb")] = target
    end

    enumerator
  end

  def test__path_enumerator__each_project_path
    project = default_project()
    enumerator = default_enumerator(project)

    assert_equal(
      Set[
        Pathname("/app/lib/lib.rb"),
        Pathname("/app/app/server/server.rb"),
        Pathname("/app/app/main/main.rb"),
        Pathname("/app/app/cli.rb"),
        Pathname("/app/test/lib_test.rb")
      ],
      enumerator.each_project_path().to_set
    )

    project.targets.find { _1.name == :lib }.tap do |target|
      target or raise

      assert_equal(
        Set[
          Pathname("/app/app/server/server.rb"),
          Pathname("/app/app/main/main.rb"),
          Pathname("/app/app/cli.rb"),
          Pathname("/app/test/lib_test.rb")
        ],
        enumerator.each_project_path(except: target).to_set
      )
    end

    project.targets.find { _1.name == :app }.tap do |target|
      target or raise

      assert_equal(
        Set[
          Pathname("/app/lib/lib.rb"),
          Pathname("/app/test/lib_test.rb")
        ],
        enumerator.each_project_path(except: target).to_set
      )
    end

    project.targets.find { _1.name == :test }.tap do |target|
      target or raise

      assert_equal(
        Set[
          Pathname("/app/lib/lib.rb"),
          Pathname("/app/app/server/server.rb"),
          Pathname("/app/app/main/main.rb"),
          Pathname("/app/app/cli.rb"),
        ],
        enumerator.each_project_path(except: target).to_set
      )
    end
  end

  def test__path_enumerator__each_target_path #: void
    project = default_project()
    enumerator = default_enumerator(project)

    project.targets.find { _1.name == :lib }.tap do |target|
      target or raise

      assert_equal(
        Set[
          Pathname("/app/lib/lib.rb"),
        ],
        enumerator.each_target_path(target).to_set
      )
    end

    project.targets.find { _1.name == :app }.tap do |target|
      target or raise

      assert_equal(
        Set[
          Pathname("/app/app/server/server.rb"),
          Pathname("/app/app/main/main.rb"),
          Pathname("/app/app/cli.rb")
        ],
        enumerator.each_target_path(target).to_set
      )

      target.groups.find { _1.name == :server }.tap do |group|
        group or raise

        assert_equal(
          Set[
            Pathname("/app/app/main/main.rb"),
            Pathname("/app/app/cli.rb")
          ],
          enumerator.each_target_path(target, except: group).to_set
        )
      end

      target.groups.find { _1.name == :main }.tap do |group|
        group or raise

        assert_equal(
          Set[
            Pathname("/app/app/server/server.rb"),
            Pathname("/app/app/cli.rb")
          ],
          enumerator.each_target_path(target, except: group).to_set
        )
      end
    end

    project.targets.find { _1.name == :test }.tap do |target|
      target or raise

      assert_equal(
        Set[
          Pathname("/app/test/lib_test.rb"),
        ],
        enumerator.each_target_path(target).to_set
      )
    end
  end

  def test__path_enumerator__each_group_path #: void
    project = default_project()
    enumerator = default_enumerator(project)

    project.targets.find { _1.name == :lib }.tap do |target|
      target or raise

      assert_equal(
        Set[
          Pathname("/app/lib/lib.rb"),
        ],
        enumerator.each_group_path(target).map { _1[0] }.to_set
      )
    end

    project.targets.find { _1.name == :app }.tap do |target|
      target or raise

      assert_equal(
        Set[
          Pathname("/app/app/cli.rb")
        ],
        enumerator.each_group_path(target).map { _1[0] }.to_set
      )

      assert_equal(
        Set[
          Pathname("/app/app/server/server.rb"),
          Pathname("/app/app/main/main.rb"),
          Pathname("/app/app/cli.rb")
        ],
        enumerator.each_group_path(target, include_sub_groups: true).map { _1[0] }.to_set
      )

      target.groups.find { _1.name == :server }.tap do |group|
        group or raise

        assert_equal(
          Set[
            Pathname("/app/app/server/server.rb"),
          ],
          enumerator.each_group_path(group).map { _1[0] }.to_set
        )
      end

      target.groups.find { _1.name == :main }.tap do |group|
        group or raise

        assert_equal(
          Set[
            Pathname("/app/app/main/main.rb"),
          ],
          enumerator.each_group_path(group).map { _1[0] }.to_set
        )
      end
    end

    project.targets.find { _1.name == :test }.tap do |target|
      target or raise

      assert_equal(
        Set[
          Pathname("/app/test/lib_test.rb"),
        ],
        enumerator.each_group_path(target).map { _1[0] }.to_set
      )
    end
  end


end
