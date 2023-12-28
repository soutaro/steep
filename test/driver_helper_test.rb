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

    super
  end

  def teardown
    super

    Steep.log_output = @log_output
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
      assert_match /rbs-collection setup is broken/, Steep.log_output.string
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
      assert_match /rbs collection install/, Steep.log_output.string
    end
  end

  def test_load_config_error__collection_not_installed
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
      YAML
      current_dir.join("test.lock.yaml").write(<<~YAML)
        path: .gem_rbs_collection
        gems: []
      YAML

      Test.new.load_config(path: path)
      assert_match /rbs collection install/, Steep.log_output.string
    end
  end
end
