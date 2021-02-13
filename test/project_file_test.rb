require_relative "test_helper"

class ProjectFileTest < Minitest::Test
  include TestHelper
  include FactoryHelper
  include SubtypingHelper

  include Steep

  def test_signature_file_load
    file = Project::SignatureFile.new(path: Pathname("hoge.rbs"))
    file.content = "class Foo end"

    file.load!

    assert_instance_of Project::SignatureFile::DeclarationsStatus, file.status
  end

  def test_signature_file_invalid_content
    file = Project::SignatureFile.new(path: Pathname("hoge.rbs"))
    file.content = "class Foo"

    file.load!

    assert_instance_of Project::SignatureFile::ParseErrorStatus, file.status
  end

  def test_source_file_with_type_check
    with_checker do |checker|
      file = Project::SourceFile.new(path: Pathname("lib/foo.rb"))
      file.content = "class Foo; end"

      assert file.type_check(checker, Time.now)

      assert_instance_of Project::SourceFile::TypeCheckStatus, file.status
    end
  end

  def test_source_file_with_no_update
    with_checker do |checker|
      file = Project::SourceFile.new(path: Pathname("lib/foo.rb"))
      file.content = "class Foo; end"

      start = Time.now
      assert file.type_check(checker, start)
      refute file.type_check(checker, start), "returns false if type checking skipped"

      assert_instance_of Project::SourceFile::TypeCheckStatus, file.status
    end
  end

  def test_source_file_syntax_error
    with_checker do |checker|
      file = Project::SourceFile.new(path: Pathname("lib/foo.rb"))
      file.content = "class Foo"

      assert file.type_check(checker, Time.now), "returns true if contains some update"

      assert_instance_of Project::SourceFile::ParseErrorStatus, file.status
    end
  end

  def test_source_file_signature_invalid
    with_checker <<RBS do |checker|
class Foo < Bar   # Bar is undefined
end
RBS
      file = Project::SourceFile.new(path: Pathname("lib/foo.rb"))
      file.content = "class Foo end"

      assert file.type_check(checker, Time.now), "returns true if contains some update"

      assert_instance_of Project::SourceFile::TypeCheckStatus, file.status
      refute_empty file.errors
    end
  end
end
