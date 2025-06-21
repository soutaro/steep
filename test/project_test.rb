require_relative "test_helper"

class ProjectTest < Minitest::Test
  include TestHelper
  include ShellHelper

  include Steep

  def dirs
    @dirs ||= []
  end

  def test_source_pattern_includes_rake_files
    pattern = Project::Pattern.new(patterns: ["lib"], extensions: [".rb", ".rake"])
    
    assert pattern =~ "lib/tasks/sample.rake"
    assert pattern =~ "lib/models/user.rb"
    refute pattern =~ "lib/assets/app.js"
  end
end
