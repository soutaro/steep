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
      sh!("bundle exec ../exe/steep interface --no-bundler -r with_steep_types ::WithSteepTypes")
    end
  end

  def test_G_option_with_invalid_gem
    chdir Pathname(__dir__) do
      _, stderr, status = sh("bundle exec ../exe/steep interface --no-bundler -r with_steep_types123 ::WithSteepTypes")

      refute_operator status, :success?
      assert_match /UnknownLibraryNameError: library=with_steep_types123/, stderr
    end
  end
end
