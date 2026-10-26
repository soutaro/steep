require_relative "../test_helper"

class Steep::Server::SignatureChangeDetectorTest < Minitest::Test
  Source = Steep::Server::SignatureChangeDetector::Source

  def path #: Pathname
    Pathname("test.rbs")
  end

  def test_source_inline_type_update
    source = Source.new(:inline, "class Foo; end")

    source.push("class Foo\nend")
    refute source.updated?

    source.push("class Bar; end")
    assert source.updated?
  end

  def test_source_rbs_formatting_and_comments
    source = Source.new(:rbs, "class Foo\n  def bar: () -> void\nend\n")

    source.push("# The class\nclass Foo\n\n  # The method\n  def bar: () -> void # comment\nend\n")
    refute source.updated?
  end

  def test_source_rbs_declarations
    source = Source.new(:rbs, "class Foo\n  def bar: () -> void\nend\n")

    source.push("class Foo\n  def bar: () -> String\nend\n")
    assert source.updated?

    source.push("class Foo\n  def bar: () -> String\n  def baz: () -> void\nend\n")
    assert source.updated?
  end

  def test_source_rbs_annotations_and_directives
    source = Source.new(:rbs, "class Foo\n  def bar: () -> void\nend\n")

    # The annotations change what the type checking does, though the declarations compare equal
    source.push("class Foo\n  %a{pure}\n  def bar: () -> void\nend\n")
    assert source.updated?

    source.push("%a{deprecated}\nclass Foo\n  %a{pure}\n  def bar: () -> void\nend\n")
    assert source.updated?

    source.push("use Foo::Bar\n%a{deprecated}\nclass Foo\n  %a{pure}\n  def bar: () -> void\nend\n")
    assert source.updated?
  end

  def test_source_rbs_syntax_error
    source = Source.new(:rbs, "class Foo\n  def bar: () -> void\nend\n")

    # The declarations stay what they were while the file cannot be parsed
    source.push("class Foo\n  def bar: () -> \nend\n")
    refute source.updated?

    source.push("class Foo\n  def bar: () -> void\nend\n")
    refute source.updated?

    source.push("class Foo\n  def bar: () -> \nend\n")
    refute source.updated?

    source.push("class Foo\n  def bar: () -> String\nend\n")
    assert source.updated?
  end

  def test_source_same_content
    source = Source.new(:rbs, "class Foo\nend\n")

    source.push("class Foo\nend\n")
    refute source.updated?

    refute source.updated?
  end

  def test_detector
    detector = Steep::Server::SignatureChangeDetector.new

    detector.add_source(path, "class Foo\nend\n", kind: :rbs)
    detector.push(path, "class Foo\n\nend\n", kind: :rbs)
    assert_equal Set[], detector.updated_paths

    detector.push(path, "class Bar\nend\n", kind: :rbs)
    assert_equal Set[path], detector.updated_paths
    assert_equal Set[], detector.updated_paths
  end

  def test_detector_new_file
    detector = Steep::Server::SignatureChangeDetector.new

    # A file without source has nothing in the environments
    detector.push(path, "class Foo\nend\n", kind: :rbs)
    assert detector.has_source?(path)
    assert_equal Set[path], detector.updated_paths
  end
end
