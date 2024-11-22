require_relative "test_helper"

class DriverHelperTest < Minitest::Test
  include Steep
  include TestHelper
  include ShellHelper

  def dirs
    @dirs ||= []
  end

  def setup
    @log_output = Steep.log_output
    Steep.log_output = StringIO.new
    @prev_level = Steep.ui_logger.level
    Steep.ui_logger.level = Logger::DEBUG

    super
  end

  def teardown
    super

    Steep.log_output = @log_output
    Steep.ui_logger.level = @prev_level
  end

  class Test
    include Steep::Drivers::Utils::DriverHelper
  end

  def test_load_config_successful__no_collection_file__no_configuration
    in_tmpdir do
      path = current_dir.join("Steepfile")
      path.write(<<~RUBY)
        target :app do
        end
      RUBY

      Test.new.load_config(path: path)
      refute_match /rbs collection install/, Steep.log_output.string
    end
  end

  def test_load_config_successful__collection_disabled
    in_tmpdir do
      path = current_dir.join("Steepfile")
      path.write(<<~RUBY)
        target :app do
          disable_collection
        end
      RUBY

      Test.new.load_config(path: path)
      refute_match /rbs collection install/, Steep.log_output.string
    end
  end

  def test_load_config_error__collection_file_missing
    in_tmpdir do
      path = current_dir.join("Steepfile")
      path.write(<<~RUBY)
        target :app do
          collection_config "test.yaml"
        end
      RUBY

      Test.new.load_config(path: path)
      assert_match /rbs-collection configuration is missing/, Steep.log_output.string
    end
  end

  def test_load_config_error__lock_file_missing
    in_tmpdir do
      path = current_dir.join("Steepfile")
      path.write(<<~RUBY)
        target :app do
          collection_config "test.yaml"
        end
      RUBY
      current_dir.join("test.yaml").write("[]")

      Test.new.load_config(path: path)
      assert_match /rbs collection install/, Steep.log_output.string
    end
  end

  def test_load_config_error__lock_file_is_broken
    in_tmpdir do
      path = current_dir.join("Steepfile")
      path.write(<<~RUBY)
        target :app do
          collection_config "test.yaml"
        end
      RUBY
      current_dir.join("test.yaml").write("[]")
      current_dir.join("test.lock.yaml").write("[")

      Test.new.load_config(path: path)
      assert_match /rbs-collection setup is broken:/, Steep.log_output.string
      assert_match /syntax error/, Steep.log_output.string
    end
  end

  def test_load_config__install_from_lockfile
    in_tmpdir do
      path = current_dir.join("Steepfile")
      path.write(<<~RUBY)
        target :app do
          collection_config "test.yaml"
        end
      RUBY
      current_dir.join("test.yaml").write(<<~YAML)
        sources:
          - name: ruby/gem_rbs_collection
            remote: https://github.com/ruby/gem_rbs_collection.git
            revision: c42c09528dd99252db98f0744181a6de54ec2f55
            repo_dir: gems

        # A directory to install the downloaded RBSs
        path: .gem_rbs_collection

        gems:
          - name: activesupport
      YAML
      current_dir.join("test.lock.yaml").write(<<~YAML)
        path: .gem_rbs_collection
        gems:
        - name: activesupport
          version: '7.0'
          source:
            type: git
            name: ruby/gem_rbs_collection
            revision: c42c09528dd99252db98f0744181a6de54ec2f55
            remote: https://github.com/ruby/gem_rbs_collection.git
            repo_dir: gems
      YAML

      Test.new.load_config(path: path)

      assert_match /Installing RBS files for collection: /, Steep.log_output.string
    end
  end

  def test_load_config__install_from_lockfile__disabled
    in_tmpdir do
      path = current_dir.join("Steepfile")
      path.write(<<~RUBY)
        target :app do
          collection_config "test.yaml"
        end
      RUBY
      current_dir.join("test.yaml").write(<<~YAML)
        sources:
          - name: ruby/gem_rbs_collection
            remote: https://github.com/ruby/gem_rbs_collection.git
            revision: c42c09528dd99252db98f0744181a6de54ec2f55
            repo_dir: gems

        # A directory to install the downloaded RBSs
        path: .gem_rbs_collection

        gems:
          - name: activesupport
      YAML
      current_dir.join("test.lock.yaml").write(<<~YAML)
        path: .gem_rbs_collection
        gems:
        - name: activesupport
          version: '7.0'
          source:
            type: git
            name: ruby/gem_rbs_collection
            revision: c42c09528dd99252db98f0744181a6de54ec2f55
            remote: https://github.com/ruby/gem_rbs_collection.git
            repo_dir: gems
      YAML

      test = Test.new
      test.disable_install_collection = true
      test.load_config(path: path)

      assert_match /rbs collection install/, Steep.log_output.string
    end
  end

  def test_load_config__install_from_lockfile__failure
    in_tmpdir do
      path = current_dir.join("Steepfile")
      path.write(<<~RUBY)
        target :app do
          collection_config "test.yaml"
        end
      RUBY
      current_dir.join("test.yaml").write(<<~YAML)
        sources:
          - name: ruby/gem_rbs_collection
            remote: https://github.com/ruby/gem_rbs_collection.git
            revision: c42c09528dd99252db98f0744181a6de54ec2f55
            repo_dir: gems

        # A directory to install the downloaded RBSs
        path: .gem_rbs_collection

        gems:
          - name: activesupport
      YAML
      current_dir.join("test.lock.yaml").write(<<~YAML)
        path: .gem_rbs_collection
        gems:
        - name: activesupport
          version: '7.0'
          source:
            type: git
            name: ruby/gem_rbs_collection
            revision: NO_SUCH_REVISION
            remote: https://github.com/ruby/gem_rbs_collection.git
            repo_dir: gems
      YAML

      test = Test.new
      test.load_config(path: path)

      assert_match /Failed to set up RBS collection:/, Steep.log_output.string
    end
  end
end
