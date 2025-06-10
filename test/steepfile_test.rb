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

  def test_config_inline #: void
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")

      Project::DSL.parse(project, <<EOF)
target :app do
  check "app", inline: true
  ignore "app/views", inline: true
end
EOF

      assert_equal 1, project.targets.size

      project.targets.find {|target| target.name == :app }.tap do |target|
        assert_instance_of Project::Target, target

        assert_equal ["app"], target.inline_source_pattern.patterns
        assert_equal ["app/views"], target.inline_source_pattern.ignores
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
      current_dir.join('rbs_collection.lock.yaml').write(<<YAML)
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

  def test_global_library_option
    in_tmpdir do
      current_dir.join('rbs_collection.yaml').write('')
      project = Project.new(steepfile_path: current_dir + "Steepfile")

      Project::DSL.parse(project, <<~RUBY)
        collection_config "test.yaml"
        library "rbs"

        target :app do
          check "app"
          ignore "app/views"

          signature "sig", "sig-private"
        end
      RUBY

      assert_instance_of Project::Options, project.global_options
      assert_equal ["rbs"], project.global_options.libraries
      assert_equal current_dir + "test.yaml", project.global_options.collection_config_path

      project.targets.find {|target| target.name == :app }.tap do |target|
        assert_instance_of Project::Target, target
        assert_equal ["rbs"], target.options.libraries
        assert_equal current_dir + "test.yaml", target.options.collection_config_path
      end
    end
  end

  def test_target_unreferenced
    in_tmpdir do
      current_dir.join('rbs_collection.yaml').write('')
      project = Project.new(steepfile_path: current_dir + "Steepfile")

      Project::DSL.parse(project, <<~RUBY)
        collection_config "test.yaml"
        library "rbs"

        target :app do
          check "app"
          ignore "app/views"
          signature "sig/app"
        end

        target :test do
          unreferenced!

          check "test"
          signature "sig/test"
        end
      RUBY

      assert_instance_of Project::Options, project.global_options
      assert_equal ["rbs"], project.global_options.libraries
      assert_equal current_dir + "test.yaml", project.global_options.collection_config_path

      project.targets.find {|target| target.name == :app }.tap do |target|
        refute_predicate target, :unreferenced
      end

      project.targets.find { _1.name == :test }.tap do |target|
        assert_predicate target, :unreferenced
      end
    end
  end

  def test_group
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")

      Project::DSL.eval(project) do
        target :app do
          group :core do
            check "lib/core"
            signature "sig/core"
          end

          group :main do
            check "lib/main"
            signature "sig/main"
          end

          check "lib/cli.rb", "exe/app"
          signature "sig/cli.rbs", "sig/exe/app.rbs"
        end
      end

      project.targets.find {|target| target.name == :app }.tap do |target|
        assert_equal [:core, :main], target.groups.map(&:name)

        assert_equal :core, target.possible_source_file?("lib/core/core.rb").name
        assert_equal :main, target.possible_source_file?("lib/main/main.rb").name
        assert_equal :app, target.possible_source_file?("lib/cli.rb").name
        assert_nil target.possible_source_file?("test/core_test.rb")

        assert_equal :core, target.possible_signature_file?("sig/core/core.rbs").name
        assert_equal :main, target.possible_signature_file?("sig/main/main.rbs").name
        assert_equal :app, target.possible_signature_file?("sig/cli.rbs").name
        assert_nil target.possible_signature_file?("sig/test/core_test.rbs")
      end
    end
  end

  def test_string
    in_tmpdir do
      project = Project.new(steepfile_path: current_dir + "Steepfile")

      Project::DSL.eval(project) do
        target "app" do
          group "core" do
          end
        end
      end

      project.targets.find {|target| target.name == :app }.tap do |target|
        assert_equal [:core], target.groups.map(&:name)
      end
    end
  end
end
