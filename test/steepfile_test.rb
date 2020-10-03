require "test_helper"

class SteepfileDSLTest < Minitest::Test
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
  vendor

  signature "sig", "sig-private"

  library "set"
  library "strong_json"
end

target :Gemfile, template: :gemfile do
end
EOF

      assert_equal 2, project.targets.size

      project.targets.find {|target| target.name == :app }.tap do |target|
        assert_instance_of Project::Target, target
        assert_equal ["app"], target.source_patterns
        assert_equal ["app/views"], target.ignore_patterns
        assert_equal ["sig", "sig-private"], target.signature_patterns
        assert_equal ["set", "strong_json"], target.options.libraries
        assert_equal Pathname("vendor/sigs"), target.options.vendor_path
        assert_equal false, target.options.allow_missing_definitions
      end

      project.targets.find {|target| target.name == :Gemfile }.tap do |target|
        assert_instance_of Project::Target, target
        assert_equal ["Gemfile"], target.source_patterns
        assert_equal [], target.ignore_patterns
        assert_equal [], target.signature_patterns
        assert_equal ["gemfile"], target.options.libraries
        assert_nil target.options.vendor_path
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
  vendor

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
end
