require_relative "../test_helper"

class Steep::Server::InlineSourceChangeDetectorTest < Minitest::Test
  def path #: Pathname
    Pathname("test.rb")
  end

  def test_detector_source_initialize
    source = Steep::Server::InlineSourceChangeDetector::Source.new("")
    source << Steep::Services::ContentChange.string("class Foo; end")

    assert source.updated?
  end

  def test_detector_source_no_type_update
    source = Steep::Server::InlineSourceChangeDetector::Source.new("class Foo; end")

    source << Steep::Services::ContentChange.string("class Foo\nend")

    refute source.updated?
  end

  def test_detector_source_type_update
    source = Steep::Server::InlineSourceChangeDetector::Source.new("class Foo; end")

    source << Steep::Services::ContentChange.string("class Bar; end")

    assert source.updated?
  end

  def test_detector
    detector = Steep::Server::InlineSourceChangeDetector.new

    detector.add_source(path, "class Foo; end")
    detector.replace_source(path, "class Bar; end")

    assert_equal Set[path], detector.type_updated_paths(Set[path])
  end

  def test_detector_unchanged
    detector = Steep::Server::InlineSourceChangeDetector.new

    detector.add_source(path, "class Foo; end")
    detector.replace_source(path, "class Foo\nend")

    assert_equal Set[], detector.type_updated_paths(Set[path])
  end

  def test_detector_no_file
    detector = Steep::Server::InlineSourceChangeDetector.new

    assert_equal Set[], detector.type_updated_paths(Set[path])
  end
end
