require_relative "test_helper"

class InitCommandTest < Minitest::Test
  include TestHelper
  include ShellHelper

  def dirs
    @dirs ||= []
  end

  def stdout
    @stdout ||= StringIO.new
  end

  def stderr
    @stderr ||= StringIO.new
  end

  def test_init
    in_tmpdir do
      Dir.chdir current_dir.to_s do
        assert_equal 0, Steep::Drivers::Init.new(stdout: stdout, stderr: stderr).run
      end

      file = current_dir + "Steepfile"
      assert_operator file, :file?
    end
  end

  def test_init_with_option
    in_tmpdir do
      Dir.chdir current_dir.to_s do
        assert_equal 0, Steep::Drivers::Init.new(stdout: stdout, stderr: stderr).tap {|init| init.steepfile = Pathname("Gemfile") }.run
      end

      refute_operator current_dir + "Steepfile", :file?
      assert_operator current_dir + "Gemfile", :file?
    end
  end

  def test_existing_file
    in_tmpdir do
      (current_dir + "Steepfile").write "old content"

      Dir.chdir current_dir.to_s do
        assert_equal 1, Steep::Drivers::Init.new(stdout: stdout, stderr: stderr).run
      end

      file = current_dir + "Steepfile"
      assert_equal "old content", file.read
    end
  end

  def test_overwrite_existing_file
    in_tmpdir do
      (current_dir + "Steepfile").write "old content"

      Dir.chdir current_dir.to_s do
        assert_equal 0, Steep::Drivers::Init.new(stdout: stdout, stderr: stderr).tap {|i| i.force_write = true }.run
      end

      file = current_dir + "Steepfile"
      refute_equal "old content", file.read
    end
  end
end
