require_relative "test_helper"

class ProjectTest < Minitest::Test
  include TestHelper
  include ShellHelper

  include Steep

  def dirs
    @dirs ||= []
  end

  def test_loader
    in_tmpdir do
      (current_dir+"lib").mkdir
      (current_dir + "lib/foo.rb").write <<CONTENT
class Foo
end
CONTENT

      (current_dir+"sig").mkdir
      (current_dir + "sig/foo.rbs").write <<CONTENT
class Foo
end
CONTENT

      project = Project.new(base_dir: current_dir)
      Project::DSL.parse(project, <<EOF)
target :lib do
  check "lib"
  signature "sig"
end
EOF
      loader = Project::FileLoader.new(project: project)
      loader.load_sources []
      loader.load_signatures

      target = project.targets[0]

      assert_equal Set[Pathname("lib/foo.rb")], Set.new(target.source_files.keys)
      assert_equal Set[Pathname("sig/foo.rbs")], Set.new(target.signature_files.keys)
    end
  end
end
