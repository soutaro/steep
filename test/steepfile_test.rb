require_relative "test_helper"

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
  check "app"
  ignore "app/views"

  stdlib_path(core_root: "vendor/rbs/core", stdlib_root: "vendor/rbs/stdlib")

  signature "sig", "sig-private"

  library "set"
  library "strong_json"
end
EOF

      assert_equal 1, project.targets.size

      project.targets.find {|target| target.name == :app }.tap do |target|
        assert_instance_of Project::Target, target
        assert_equal ["app"], target.source_pattern.patterns
        assert_equal ["app/views"], target.source_pattern.ignores
        assert_equal ["sig", "sig-private"], target.signature_pattern.patterns
        assert_equal ["set", "strong_json"], target.options.libraries
        assert_equal Pathname("vendor/rbs/core"), target.options.paths.core_root
        assert_equal Pathname("vendor/rbs/stdlib"), target.options.paths.stdlib_root
      end
    end
  end

  def test_config_typing_options
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")

      begin
        Steep.log_output = StringIO.new

        Project::DSL.parse(project, <<RUBY)
target :app do
  check "app"
  ignore "app/views"

  typing_options :strict,
                 allow_missing_definitions: true,
                 allow_fallback_any: true
end
RUBY

        assert_match(/\[Steepfile\] \[target=app\] #typing_options is deprecated and has no effect as of version 0\.46\.0\. Update your Steepfile as follows for \(almost\) equivalent setting:/, Steep.log_output.string)
        assert_match(/configure_code_diagnostics\(D::Ruby\.strict\)/, Steep.log_output.string)
        assert_match(/hash\[D::Ruby::MethodDefinitionMissing\] = nil/, Steep.log_output.string)
        assert_match(/hash\[D::Ruby::FallbackAny\] = nil/, Steep.log_output.string)
      ensure
        Steep.log_output = STDERR
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

  def test_diagnostics
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")

      Project::DSL.parse(project, <<RUBY)
target :app do
  repo_path "vendor/rbs/internal"

  configure_code_diagnostics(
    {
      Steep::Diagnostic::Ruby::FallbackAny => :warning
    }
  )
end
RUBY

      project.targets[0].tap do |target|
        assert_equal :warning, target.code_diagnostics_config[Diagnostic::Ruby::FallbackAny]
      end
    end
  end

  def test_collection_implicit
    in_tmpdir do
      current_dir.join('rbs_collection.yaml').write('')
      current_dir.join('rbs_collection.lock.yaml').write(<<YAML)
sources: []
path: '.gem_rbs_collection'
gems:
  - name: securerandom
    source:
      type: stdlib
YAML
      project = Project.new(steepfile_path: current_dir + "Steepfile")

      Project::DSL.parse(project, <<EOF)
target :app do
end
EOF

      project.targets[0].tap do |target|
        assert_equal current_dir.join('rbs_collection.yaml'), target.options.collection_config_path
      end
    end
  end

  def test_collection_explicit
    in_tmpdir do
      current_dir.join('my-rbs_collection.yaml').write('')
      current_dir.join('my-rbs_collection.lock.yaml').write(<<YAML)
sources: []
path: '.gem_rbs_collection'
gems:
  - name: securerandom
    source:
      type: stdlib
YAML
      project = Project.new(steepfile_path: current_dir + "Steepfile")

      Project::DSL.parse(project, <<EOF)
target :app do
  collection_config 'my-rbs_collection.yaml'
end
EOF

      project.targets[0].tap do |target|
        assert_equal current_dir.join('my-rbs_collection.yaml'), target.options.collection_config_path
      end
    end
  end

  def test_disable_collection
    in_tmpdir do
      current_dir.join('rbs_collection.yaml').write('')
      current_dir.join('rbs_collection.lock.yaml').write(<<YAML)
sources: []
path: '.gem_rbs_collection'
gems:
  - name: pathname
    source:
      type: stdlib
YAML
      project = Project.new(steepfile_path: current_dir + "Steepfile")

      Project::DSL.parse(project, <<EOF)
target :app do
  disable_collection
end
EOF

      project.targets[0].tap do |target|
        assert_nil target.options.collection_lock
      end
    end
  end

  def test_collection_missing
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")

      Project::DSL.parse(project, <<~RUBY)
        target :app do
        end
      RUBY

      assert_nil project.targets[0].options.load_collection_lock
      assert_nil project.targets[0].options.collection_lock
    end
  end

  def test_load_collection_missing_error
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")

      Project::DSL.parse(project, <<~RUBY)
        target :app do
        end
      RUBY

      assert_nil project.targets[0].options.load_collection_lock()
      assert_nil project.targets[0].options.collection_lock
    end
  end


  def test_load_collection_syntax_error
    in_tmpdir do
      current_dir.join('rbs_collection.yaml').write('')
      current_dir.join('rbs_collection.lock.yaml').write(']')
      project = Project.new(steepfile_path: current_dir + "Steepfile")

      Project::DSL.parse(project, <<~RUBY)
        target :app do
        end
      RUBY

      assert_instance_of YAML::SyntaxError, project.targets[0].options.load_collection_lock
      assert_nil project.targets[0].options.collection_lock
    end
  end

  def test_load_collection_failed
    in_tmpdir do
      current_dir.join('rbs_collection.yaml').write('')
      current_dir.join('rbs_collection.lock.yaml').write(<<~YAML)
        path: .test_path
        gems: []
      YAML
      project = Project.new(steepfile_path: current_dir + "Steepfile")

      Project::DSL.parse(project, <<~RUBY)
        target :app do
        end
      RUBY

      assert_instance_of RBS::Collection::Config::CollectionNotAvailable, project.targets[0].options.load_collection_lock
      assert_nil project.targets[0].options.collection_lock
    end
  end
end
