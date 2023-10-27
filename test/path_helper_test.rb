require_relative "test_helper"

class PathHelperTest < Minitest::Test
  include Steep
  include TestHelper
  include PathHelper

  def test_to_pathname
    # Unix path
    assert_equal Pathname("/foo/bar"), to_pathname("file:///foo/bar")
    assert_equal Pathname("/foo/bar"), to_pathname("file:/foo/bar")
    assert_equal Pathname("/foo bar"), to_pathname("file:/foo%20bar")

    # Dosish path
    assert_equal Pathname("C:/foo/bar"), to_pathname("file:///C:/foo/bar", dosish: true)

    # Non file: URI
    assert_nil to_pathname("http://foo/bar.baz")
    assert_nil to_pathname("untitled:Untitled-1")
  end

  def test_to_uri
    assert_equal URI("file:///foo/bar"), to_uri(Pathname("/foo/bar"))
    assert_equal URI("file:///c:/foo/bar"), to_uri(Pathname("c:/foo/bar"), dosish: true)
    assert_equal URI("file:///foo%20bar"), to_uri(Pathname("/foo bar"))
  end
end
