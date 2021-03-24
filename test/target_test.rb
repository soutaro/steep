require "test_helper"

module Steep
  class TargetTest < Minitest::Test
    include TestHelper

    def test_environment_loader
      Dir.mktmpdir do |dir|
        path = Pathname(dir)

        (path + "vendor/repo").mkpath
        (path + "vendor/core").mkpath

        project = Project.new(steepfile_path: path + "Steepfile")

        Project::Target.construct_env_loader(
          options: Project::Options.new.tap {|opts|
            opts.repository_paths << path + "vendor/repo"
          },
          project: project
        ).tap do |loader|
          refute_nil loader.core_root

          assert_includes loader.repository.dirs, RBS::Repository::DEFAULT_STDLIB_ROOT
          assert_includes loader.repository.dirs, path + "vendor/repo"
        end

        Project::Target.construct_env_loader(
          options: Project::Options.new.tap {|opts|
            opts.vendor_path = path + "vendor/core"
            opts.repository_paths << path + "vendor/repo"
          },
          project: project
        ).tap do |loader|
          assert_nil loader.core_root

          assert_includes loader.dirs, path + "vendor/core"
          refute_includes loader.repository.dirs, RBS::Repository::DEFAULT_STDLIB_ROOT
          assert_includes loader.repository.dirs, path + "vendor/repo"
        end
      end
    end
  end
end
