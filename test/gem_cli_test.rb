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
    chdir Pathname(__dir__).parent do
      sh!("bundle exec exe/steep interface --no-bundler -G with_steep_types ::WithSteepTypes")
    end
  end

  def test_G_option_with_invalid_gem
    chdir Pathname(__dir__).parent do
      _, stderr, status = sh("bundle exec exe/steep interface --no-bundler -G with_steep_types123 ::WithSteepTypes")

      refute_operator status, :success?
      assert_match /MissingSpecError/, stderr
    end
  end

  def test_bundler_load
    chdir Pathname(__dir__).parent do
      sh!("bundle exec exe/steep interface ::WithSteepTypes")
    end
  end

  def test_no_bundler_option
    chdir Pathname(__dir__).parent do
      _, _, status = sh("bundle exec exe/steep interface --no-bundler ::WithSteepTypes")

      refute_operator status, :success?
    end
  end
end
