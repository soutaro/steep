require_relative "../test_helper"

class Source__IgnoredRangeTest < Minitest::Test
  include FactoryHelper

  def no_method_error(source:, line:)
    node = source.find_nodes(line: line, column: 1).first
    Steep::Diagnostic::Ruby::NoMethod.new(node: node, type: nil, method: nil)
  end

  def unsupported_syntax_error(source:, line:)
    node = source.find_nodes(line: line, column: 1).first
    Steep::Diagnostic::Ruby::UnsupportedSyntax.new(node: node)
  end

  def fallback_any_error(source:, line:)
    node = source.find_nodes(line: line, column: 1).first
    Steep::Diagnostic::Ruby::FallbackAny.new(node: node)
  end

  def test_ignored_all_include?
    with_factory do |factory|
      source = Steep::Source.parse(<<~RUBY, path: Pathname("foo.rb"), factory: factory)
        error
        # steep:ignore all
        error
        # steep:ignore end
        error
      RUBY

      from = Steep::Source::DirectiveComment.new(source.find_comment(line: 2, column: 1))
      to = Steep::Source::DirectiveComment.new(source.find_comment(line: 4, column: 1))
      range = Steep::Source::IgnoredRange.new(from: from, to: to)
      assert_equal false, range.include?(no_method_error(source: source, line: 1))
      assert_equal true, range.include?(no_method_error(source: source, line: 3))
      assert_equal false, range.include?(no_method_error(source: source, line: 5))

      assert_equal true, range.include?(fallback_any_error(source: source, line: 3))
    end
  end

  def test_ignore_specific_include?
    with_factory do |factory|
      source = Steep::Source.parse(<<~RUBY, path: Pathname("foo.rb"), factory: factory)
        error
        # steep:ignore NoMethod, UnsupportedSyntax
        error
        # steep:ignore end
        error
      RUBY

      from = Steep::Source::DirectiveComment.new(source.find_comment(line: 2, column: 1))
      to = Steep::Source::DirectiveComment.new(source.find_comment(line: 4, column: 1))
      range = Steep::Source::IgnoredRange.new(from: from, to: to)
      assert_equal false, range.include?(no_method_error(source: source, line: 1))
      assert_equal true, range.include?(no_method_error(source: source, line: 3))
      assert_equal false, range.include?(no_method_error(source: source, line: 5))

      assert_equal true, range.include?(unsupported_syntax_error(source: source, line: 3))
      assert_equal false, range.include?(fallback_any_error(source: source, line: 3))
    end
  end

  def test_half_opened_range_include?
    with_factory do |factory|
      source = Steep::Source.parse(<<~RUBY, path: Pathname("foo.rb"), factory: factory)
        error
        # steep:ignore all
        error
      RUBY

      from = Steep::Source::DirectiveComment.new(source.find_comment(line: 2, column: 1))
      range = Steep::Source::IgnoredRange.new(from: from, to: nil)
      assert_equal false, range.include?(no_method_error(source: source, line: 1))
      assert_equal true, range.include?(no_method_error(source: source, line: 3))
    end
  end
end
