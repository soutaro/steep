require_relative "test_helper"

class ProjectTest < Minitest::Test
  include TestHelper
  include ShellHelper

  include Steep

  def dirs
    @dirs ||= []
  end
end
