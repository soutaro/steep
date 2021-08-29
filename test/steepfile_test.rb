require "test_helper"

class SteepfileTest < Minitest::Test
  include Steep
  include TestHelper
  include ShellHelper

  def dirs
    @dirs ||= []
  end

  def test_config
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")

      Project::DSL.parse(project, <<EOF)
target :app do
  typing_options :strict
  check "app"
  ignore "app/views"

  stdlib_path(core_root: "vendor/rbs/core", stdlib_root: "vendor/rbs/stdlib")

  signature "sig", "sig-private"

  library "set"
  library "strong_json"
end

target :Gemfile, template: :gemfile do
  stdlib_path(core_root: false, stdlib_root: false)
end
EOF

      assert_equal 2, project.targets.size

      project.targets.find {|target| target.name == :app }.tap do |target|
        assert_instance_of Project::Target, target
        assert_equal ["app"], target.source_pattern.patterns
        assert_equal ["app/views"], target.source_pattern.ignores
        assert_equal ["sig", "sig-private"], target.signature_pattern.patterns
        assert_equal ["set", "strong_json"], target.options.libraries
        assert_equal Pathname("vendor/rbs/core"), target.options.paths.core_root
        assert_equal Pathname("vendor/rbs/stdlib"), target.options.paths.stdlib_root
        assert_equal false, target.options.allow_missing_definitions
      end

      project.targets.find {|target| target.name == :Gemfile }.tap do |target|
        assert_instance_of Project::Target, target
        assert_equal ["Gemfile"], target.source_pattern.patterns
        assert_equal [], target.source_pattern.ignores
        assert_equal [], target.signature_pattern.patterns
        assert_equal ["gemfile"], target.options.libraries
        assert_equal false, target.options.paths.core_root
        assert_equal false, target.options.paths.stdlib_root
        assert_equal true, target.options.allow_missing_definitions
      end
    end
  end

  def test_config_typing_options
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")

      Project::DSL.parse(project, <<RUBY)
target :app do
  check "app"
  ignore "app/views"

  typing_options :strict,
                 allow_missing_definitions: true,
                 allow_fallback_any: true
end
RUBY

      assert_equal 1, project.targets.size

      target = project.targets[0]

      assert_operator target.options, :allow_missing_definitions
      assert_operator target.options, :allow_fallback_any
      refute_operator target.options, :allow_unknown_constant_assignment
      refute_operator target.options, :allow_unknown_method_calls
    end
  end

  def test_invalid_template
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")

      assert_raises RuntimeError do
        Project::DSL.parse(project, <<EOF)
target :Gemfile, template: :gemfile2
EOF
      end
    end
  end

  def test_repo_path
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")

      Project::DSL.parse(project, <<EOF)
target :app do
  repo_path "vendor/rbs/internal"
end
EOF
      project.targets[0].tap do |target|
        assert_equal [Pathname("vendor/rbs/internal")], target.options.paths.repo_paths
      end
    end
  end
end
