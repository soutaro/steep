require_relative "test_helper"

class PatternTest < Minitest::Test
  include Steep

  def test_pattern
    pattern = Project::Pattern.new(
      patterns: ["app/models", "app/controllers/**/*.rb"],
      extensions: [".rb"]
    )

    assert_operator pattern, :=~, "app/models/account.rb"
    assert_operator pattern, :=~, "app/controllers/admin_controller.rb"
    assert_operator pattern, :=~, "app/controllers/api/v2/accounts_controller.rb"
  end

  def test_pattern_with_glob
    pattern = Project::Pattern.new(
      patterns: ["app/models/*/bar"],
      extensions: [".rb"]
    )

    assert_operator pattern, :=~, "app/models/foo/bar/baz.rb"
    assert_operator pattern, :=~, "app/models/foo/bar/baz/qux.rb"
  end

  def test_pattern_with_multiple_extensions
    pattern = Project::Pattern.new(
      patterns: ["app/models"],
      extensions: [".rb", ".rake"]
    )

    assert_operator pattern, :=~, "app/models/account.rb"
    assert_operator pattern, :=~, "app/models/account.rake"
    refute_operator pattern, :=~, "app/models/account.py"
  end

  def test_pattern_backward_compatibility_with_ext
    pattern = Project::Pattern.new(
      patterns: ["app/models"],
      ext: ".rb"
    )

    assert_operator pattern, :=~, "app/models/account.rb"
    refute_operator pattern, :=~, "app/models/account.rake"
  end
end
