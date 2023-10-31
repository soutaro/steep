require_relative "test_helper"

class PatternTest < Minitest::Test
  include Steep

  def test_pattern
    pattern = Project::Pattern.new(
      patterns: ["app/models", "app/controllers/**/*.rb"],
      ext: ".rb"
    )

    assert_operator pattern, :=~, "app/models/account.rb"
    assert_operator pattern, :=~, "app/controllers/admin_controller.rb"
    assert_operator pattern, :=~, "app/controllers/api/v2/accounts_controller.rb"
  end
end
