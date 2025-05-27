require_relative "../test_helper"

class SourceIgnoreRangesTest < Minitest::Test
  include Steep

  include TestHelper

  def parse(source_code)
    _, comments = Source.new_parser().parse_with_comments(
      ::Parser::Source::Buffer.new("a.rb", 1, source: source_code)
    )

    buffer = RBS::Buffer.new(name: Pathname("a.rb"), content: source_code)

    ignores = comments.filter_map do |comment|
      AST::Ignore.parse(comment, buffer)
    end

    [Source::IgnoreRanges.new(ignores: ignores), buffer]
  end

  def test_ignore_ranges
    ranges, _ = parse(<<~RUBY)
      # steep:ignore:start

      # steep:ignore:end

      1 + 2 # steep:ignore

      # steep:ignore:start
      # steep:ignore:start
      foo() # steep:ignore
      # steep:ignore:end
      # steep:ignore:end
    RUBY

    assert_equal(1..3, ranges.ignored_ranges[0])
    assert_operator ranges.ignored_lines, :key?, 5
    assert_equal(8..10, ranges.ignored_ranges[1])

    refute_operator ranges.ignored_lines, :key?, 9
    assert_equal 3, ranges.error_ignores.size
  end

  def location_at_line(buffer, start_line, end_line = start_line)
    RBS::Location.new(
      buffer,
      buffer.loc_to_pos([start_line, 0]),
      buffer.loc_to_pos([end_line, 0])
    )
  end

  def test_ignore?
    ranges, buf = parse(<<~RUBY)
      # steep:ignore:start


      # steep:ignore:end

      1 + 2 # steep:ignore

      1 + 2 # steep:ignore NoMethod
    RUBY

    assert ranges.ignore?(2, 2, "FOO")
    assert ranges.ignore?(2, 3, "FOO")

    refute ranges.ignore?(3, 5, "FOO")
    refute ranges.ignore?(5, 5, "FOO")

    assert ranges.ignore?(6, 6, "FOO")
    assert ranges.ignore?(6, 7, "FOO")
    assert ranges.ignore?(5, 6, "FOO")

    assert ranges.ignore?(8, 8, "Ruby::NoMethod")
    refute ranges.ignore?(8, 8, "FOO")
  end

  def test_redundant_ignores
    ranges, buf = parse(<<~RUBY)
      # steep:ignore:start
      1 + ""
      # steep:ignore:end

      # steep:ignore:start
      1 + 2
      # steep:ignore:end

      1 + "" # steep:ignore

      1 + 2 # steep:ignore
    RUBY

    ignores = ranges.redundant_ignores([1, 8])

    assert_equal 5, ignores[0].line
    assert_equal 7, ignores[1].line
    assert_equal 11, ignores[3].line
  end
end
