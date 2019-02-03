require_relative "test_helper"

class ProjectFileTest < Minitest::Test
  include TestHelper
  include SubtypingHelper
  include Steep

  def test_signature_file_without_content
    file = Project::SignatureFile.new(path: Pathname("hoge.rbi"))

    assert_equal "", file.content
    refute_nil file.content_updated_at
    assert_empty file.parse
  end

  def test_signature_file_with_content
    file = Project::SignatureFile.new(path: Pathname("hoge.rbi"))
    original_updated_at = file.content_updated_at
    sleep 0.1

    file.content = "class Foo end"

    refute_equal original_updated_at, file.content_updated_at
    refute_empty file.parse
  end

  def test_signature_file_with_invalid_content
    file = Project::SignatureFile.new(path: Pathname("hoge.rbi"))
    original_updated_at = file.content_updated_at
    sleep 0.1

    file.content = "class Foo"

    refute_equal original_updated_at, file.content_updated_at
    assert_raises(Racc::ParseError) { file.parse }
  end

  def options
    Project::Options.new
  end

  def test_source_file_without_content
    file = Project::SourceFile.new(path: Pathname("foo.rb"), options: options)

    assert_equal "", file.content
    refute_nil file.content_updated_at
    assert_nil file.source
    assert_nil file.typing
    assert_nil file.last_type_checked_at
    assert file.requires_type_check?
  end

  def test_source_file_with_content
    file = Project::SourceFile.new(path: Pathname("hoge.rb"), options: options)
    original_updated_at = file.content_updated_at
    sleep 0.1

    file.content = "class Foo end"

    refute_equal original_updated_at, file.content_updated_at
  end

  def test_source_file_parse
    file = Project::SourceFile.new(path: Pathname("hoge.rb"), options: options)
    file.content = "class Foo end"

    assert_instance_of Source, file.parse
    assert_instance_of Source, file.source
  end

  def test_source_file_parse_error
    file = Project::SourceFile.new(path: Pathname("hoge.rb"), options: options)
    file.content = "class Foo"

    file.parse

    assert_instance_of ::Parser::SyntaxError, file.source
  end

  def test_source_file_errors
    file = Project::SourceFile.new(path: Pathname("hoge.rb"), options: options)
    file.content = "class Foo end"

    assert_nil file.errors
  end

  def test_type_check
    file = Project::SourceFile.new(path: Pathname("hoge.rb"), options: options)
    file.content = "@foo"

    check = new_subtyping_checker

    file.parse
    file.type_check(check)

    refute_nil file.typing
    assert_empty file.errors
  end

  def test_type_check_with_option
    file = Project::SourceFile.new(path: Pathname("hoge.rb"), options: options)
    file.content = "@foo"
    file.options.fallback_any_is_error = true

    check = new_subtyping_checker

    file.parse
    file.type_check(check)

    refute_nil file.typing
    refute_empty file.errors
  end

  class AccumulateListener
    attr_reader :trace

    def reset!
      trace.clear
    end

    def initialize
      @trace = []
    end

    def method_missing(name, *args, &block)
      trace << [name, *args, block]
      yield
    end

    def test
      trace.clear
      sleep 0.01
      yield
    end
  end

  def test_project_no_listener
    project = Project.new()
    project.signature_files[Pathname("builtin.rbi")] = Project::SignatureFile.new(path: Pathname("builtin.rbi")).tap do |file|
      file.content = BUILTIN
    end
    project.source_files[Pathname("foo.rb")] = Project::SourceFile.new(path: Pathname("foo.rb"), options: options).tap do |file|
      file.content = "1 + 2"
    end

    project.type_check
    assert_instance_of Project::SignatureLoaded, project.signature
    refute project.has_type_error?
  end

  def test_project_listener
    listener = AccumulateListener.new

    project = Project.new(listener)
    project.signature_files[Pathname("builtin.rbi")] = Project::SignatureFile.new(path: Pathname("builtin.rbi")).tap do |file|
      file.content = BUILTIN
    end
    project.source_files[Pathname("foo.rb")] = Project::SourceFile.new(path: Pathname("foo.rb"), options: options).tap do |file|
      file.content = "1 + 2"
    end
    project.source_files[Pathname("bar.rb")] = Project::SourceFile.new(path: Pathname("foo.rb"), options: options).tap do |file|
      file.content = "puts :foo"
    end

    listener.test do
      project.type_check

      assert_equal [:check,
                    :load_signature, :parse_signature, :validate_signature,
                    :parse_source, :type_check_source,
                    :parse_source, :type_check_source],
                   listener.trace.map(&:first)
    end

    listener.test do
      # When nothing is updated, it just skips type checking
      project.type_check

      assert_equal [:check],
                   listener.trace.map(&:first)
    end

    listener.test do
      # When source content is updated, the file is type checked
      project.source_files[Pathname("foo.rb")].content = "1 + 3"
      project.type_check

      assert_equal [:check, :parse_source, :type_check_source],
                   listener.trace.map(&:first)
    end

    listener.test do
      # When signature content is updated, all files are type checked
      project.signature_files[Pathname("foo.rbi")] = Project::SignatureFile.new(path: Pathname("foo.rbi")).tap do |file|
        file.content = "class Foo end"
      end
      project.type_check

      assert_equal [:check,
                    :load_signature, :parse_signature, :parse_signature,
                    :validate_signature,
                    :parse_source, :type_check_source,
                    :parse_source, :type_check_source],
                   listener.trace.map(&:first)
    end

    listener.test do
      # When signature is deleted, all files are type checked
      project.signature_files.delete(Pathname("foo.rbi"))

      project.type_check

      assert_equal [:check,
                    :load_signature, :parse_signature,
                    :validate_signature,
                    :parse_source, :type_check_source,
                    :parse_source, :type_check_source],
                   listener.trace.map(&:first)
    end

    listener.test do
      # Clearing project resets type check results
      project.clear

      project.type_check

      assert_equal [:clear_project,
                    :check,
                    :load_signature, :parse_signature,
                    :validate_signature,
                    :parse_source, :type_check_source,
                    :parse_source, :type_check_source],
                   listener.trace.map(&:first)
    end
  end
end
