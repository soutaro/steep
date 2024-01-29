require_relative "../test_helper"

class AST__IgnoreTest < Minitest::Test
  include TestHelper

  Ignore = Steep::AST::Ignore

  def parse(ruby)
    buffer = ::Parser::Source::Buffer.new("a.rb", 1, source: ruby)
    node, comments = Parser::Ruby33.new.parse_with_comments(buffer)

    [node, comments, RBS::Buffer.new(name: "a.rb", content: ruby)]
  end

  def test_parse_ignore_start
    _, comments, buf = parse(<<~RUBY)
      # steep:ignore:start
      # steep:ignore:start123
      # steep:ignore:start hello
    RUBY

    Steep::AST::Ignore.parse(comments[0], buf).tap do |ignore|
      assert_instance_of Ignore::IgnoreStart, ignore

      assert_equal 1, ignore.line
      assert_equal "steep:ignore:start", ignore.location.source
    end

    assert_nil Steep::AST::Ignore.parse(comments[1], buf)
    assert_nil Steep::AST::Ignore.parse(comments[2], buf)
  end

  def test_parse_ignore_end
    _, comments, buf = parse(<<~RUBY)
      # steep:ignore:end
      # steep:ignore:end123
      # steep:ignore:end world
    RUBY

    Steep::AST::Ignore.parse(comments[0], buf).tap do |ignore|
      assert_instance_of Ignore::IgnoreEnd, ignore

      assert_equal 1, ignore.line
      assert_equal "steep:ignore:end", ignore.location.source
    end

    assert_nil Steep::AST::Ignore.parse(comments[1], buf)
    assert_nil Steep::AST::Ignore.parse(comments[2], buf)
  end

  def test_parse_ignore__empty
    _, comments, buf = parse(<<~RUBY)
      # steep:ignore
      # steep:ignore123
    RUBY

    Steep::AST::Ignore.parse(comments[0], buf).tap do |ignore|
      assert_instance_of Ignore::IgnoreLine, ignore

      assert_equal 1, ignore.line
      assert_empty ignore.raw_diagnostics
      assert_equal :all, ignore.ignored_diagnostics
      assert_equal "steep:ignore", ignore.location.source
    end

    assert_nil Steep::AST::Ignore.parse(comments[1], buf)
  end

  def test_parse_ignore__all
    _, comments, buf = parse(<<~RUBY)
      # steep:ignore
      # steep:ignore123
    RUBY

    Steep::AST::Ignore.parse(comments[0], buf).tap do |ignore|
      assert_instance_of Ignore::IgnoreLine, ignore

      assert_equal 1, ignore.line
      assert_empty ignore.raw_diagnostics
      assert_equal :all, ignore.ignored_diagnostics
      assert_equal "steep:ignore", ignore.location.source
    end

    assert_nil Steep::AST::Ignore.parse(comments[1], buf)
  end

  def test_parse_ignore__diagnostics
    _, comments, buf = parse(<<~RUBY)
      # steep:ignore Foo
      # steep:ignore Foo, Bar,
    RUBY

    Steep::AST::Ignore.parse(comments[0], buf).tap do |ignore|
      assert_instance_of Ignore::IgnoreLine, ignore

      assert_equal 1, ignore.line
      refute_empty ignore.raw_diagnostics
      assert_equal ["Foo"], ignore.ignored_diagnostics
      assert_equal "steep:ignore Foo", ignore.location.source
    end

    Steep::AST::Ignore.parse(comments[1], buf).tap do |ignore|
      assert_instance_of Ignore::IgnoreLine, ignore

      assert_equal 2, ignore.line
      refute_empty ignore.raw_diagnostics
      assert_equal ["Foo", "Bar"], ignore.ignored_diagnostics
      assert_equal "steep:ignore Foo, Bar,", ignore.location.source
    end
  end
end
