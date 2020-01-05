require "test_helper"

class SteepfileDSLTest < Minitest::Test
  include Steep

  def project
    @project ||= Project.new
  end

  def test_config
    Project::DSL.parse(project, <<EOF)
target :app do
  check "app"
  ignore "app/views"
  vendor

  signature "sig", "sig-private"

  library "set"
  library "strong_json"
end

target :Gemfile, template: :gemfile
EOF
    assert_equal 2, project.targets.size

    project.targets.find {|target| target.name == :app }.tap do |target|
      assert_instance_of Project::Target, target
      assert_equal ["app"], target.source_patterns
      assert_equal ["app/views"], target.ignore_patterns
      assert_equal ["sig", "sig-private"], target.signature_patterns
      assert_equal ["set", "strong_json"], target.options.libraries
      assert_equal Pathname("vendor/sigs/stdlib"), target.options.vendored_stdlib_path
      assert_equal Pathname("vendor/sigs/gems"), target.options.vendored_gems_path
    end

    project.targets.find {|target| target.name == :Gemfile }.tap do |target|
      assert_instance_of Project::Target, target
      assert_equal ["Gemfile"], target.source_patterns
      assert_equal [], target.ignore_patterns
      assert_equal [], target.signature_patterns
      assert_equal ["gemfile"], target.options.libraries
      assert_nil target.options.vendored_stdlib_path
      assert_nil target.options.vendored_gems_path
    end
  end

  def test_invalid_template
    assert_raises RuntimeError do
      Project::DSL.parse(project, <<EOF)
target :Gemfile, template: :gemfile2
EOF
    end
  end
end
