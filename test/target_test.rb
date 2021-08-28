require "test_helper"

module Steep
  class TargetTest < Minitest::Test
    include TestHelper

    def with_dir
      Dir.mktmpdir do |dir|
        path = Pathname(dir)

        (path + "vendor/repo").mkpath
        (path + "vendor/core").mkpath
        (path + "vendor/stdlib").mkpath

        project = Project.new(steepfile_path: path + "Steepfile")
        yield project, path
      end
    end

    def test_environment_loader_default
      with_dir do |project, path|
        options = Project::Options.new()
        options.paths.core_root = nil
        options.paths.stdlib_root = nil

        Project::Target.construct_env_loader(options: options, project: project).tap do |loader|
          assert_equal RBS::EnvironmentLoader::DEFAULT_CORE_ROOT, loader.core_root
          assert_includes loader.repository.dirs, RBS::Repository::DEFAULT_STDLIB_ROOT
        end
      end
    end

    def test_environment_loader_custom
      with_dir do |project, path|
        options = Project::Options.new()
        options.paths.core_root = Pathname("vendor/core")
        options.paths.stdlib_root = Pathname("vendor/stdlib")
        options.paths.repo_paths << Pathname("vendor/repo")

        Project::Target.construct_env_loader(options: options, project: project).tap do |loader|
          assert_equal path + "vendor/core", loader.core_root
          assert_includes loader.repository.dirs, path + "vendor/stdlib"
          assert_includes loader.repository.dirs, path + "vendor/repo"
        end
      end
    end

    def test_environment_loader_none
      with_dir do |project, path|
        options = Project::Options.new()
        options.paths.core_root = false
        options.paths.stdlib_root = false

        Project::Target.construct_env_loader(options: options, project: project).tap do |loader|
          assert_nil loader.core_root
          assert_empty loader.repository.dirs
        end
      end
    end
  end
end
