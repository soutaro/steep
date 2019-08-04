require_relative 'test_helper'

class GemCLITest < Minitest::Test
  include ShellHelper

  def dirs
    @dirs ||= []
  end

  def envs
    @envs ||= []
  end

  def test_G_option
    chdir Pathname(__dir__) do
      sh!("bundle exec ../exe/steep interface --no-bundler -G with_steep_types ::WithSteepTypes")
    end
  end

  def test_G_option_with_invalid_gem
    chdir Pathname(__dir__) do
      _, stderr, status = sh("bundle exec ../exe/steep interface --no-bundler -G with_steep_types123 ::WithSteepTypes")

      refute_operator status, :success?
      assert_match /Gem not found: name=with_steep_types123, version=/, stderr
    end
  end

  def test_G_option_does_not_have_duplicated_paths
    chdir Pathname(__dir__) do
      stdout, _ = sh!("bundle exec ../exe/steep paths --no-bundler -G with_steep_types -G with_steep_types -I gems/with_steep_types/sig ::WithSteepTypes")
      lines = stdout.lines.map(&:chomp).map(&:strip)
      assert_includes lines, "gems/with_steep_types/sig"

      skip "Not sure why we need this feature"
      assert_equal 1, lines.count {|line| line =~ /with_steep_types/ }
    end
  end

  def test_G_option_with_gem_without_types
    chdir Pathname(__dir__) do
      _, stderr, status = sh("bundle exec ../exe/steep interface --no-bundler -G without_steep_types ::Integer")

      refute_operator status, :success?
      assert_match /Type definition directory not found: without_steep_types \(1.0.0\)/, stderr
    end
  end

  def test_bundler_load
    chdir Pathname(__dir__) do
      sh!("bundle exec ../exe/steep interface ::WithSteepTypes")
    end
  end

  def test_no_bundler_option
    chdir Pathname(__dir__) do
      _, _, status = sh("bundle exec ../exe/steep interface --no-bundler ::WithSteepTypes")

      refute_operator status, :success?
    end
  end
end
