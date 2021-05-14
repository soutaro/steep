require "test_helper"

class FileLoaderTest < Minitest::Test
  include Steep
  include TestHelper
  include ShellHelper

  Pattern = Project::Pattern
  FileLoader = Services::FileLoader

  def dirs
    @dirs ||= []
  end

  def test_each_path_in_patterns
    in_tmpdir do
      loader = FileLoader.new(base_dir: current_dir)

      (current_dir + "lib").mkdir()
      (current_dir + "test").mkdir()
      (current_dir + "lib/foo.rb").write("")
      (current_dir + "lib/parser.y").write("")
      (current_dir + "test/foo_test.rb").write("")
      (current_dir + "Rakefile").write("")

      pat = Pattern.new(patterns: ["lib", "test"], ext: ".rb")

      assert_equal [Pathname("lib/foo.rb"), Pathname("test/foo_test.rb")], loader.each_path_in_patterns(pat).to_a
      assert_equal [Pathname("lib/foo.rb")], loader.each_path_in_patterns(pat, ["lib"]).to_a
      assert_empty loader.each_path_in_patterns(pat, ["lib/parser.y"]).to_a
      assert_empty loader.each_path_in_patterns(pat, ["Rakefile"]).to_a
    end
  end
end
