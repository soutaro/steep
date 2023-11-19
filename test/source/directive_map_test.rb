require_relative "../test_helper"

class Source__DirectiveMapTest < Minitest::Test
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

  def test_ignored_all_ignored?
    with_factory do |factory|
      source = Steep::Source.parse(<<~RUBY, path: Pathname("foo.rb"), factory: factory)
        error
        # steep:ignore all
        error
        # steep:ignore end
        error
      RUBY

      directive_map = Steep::Source::DirectiveMap.new(source.comments)
      assert_equal false, directive_map.ignored?(no_method_error(source: source, line: 1))
      assert_equal true, directive_map.ignored?(no_method_error(source: source, line: 3))
      assert_equal false, directive_map.ignored?(no_method_error(source: source, line: 5))

      assert_equal true, directive_map.ignored?(fallback_any_error(source: source, line: 3))
    end
  end

  def test_ignore_specific_ignored?
    with_factory do |factory|
      source = Steep::Source.parse(<<~RUBY, path: Pathname("foo.rb"), factory: factory)
        error
        # steep:ignore NoMethod, UnsupportedSyntax
        error
        # steep:ignore end
        error
      RUBY

      directive_map = Steep::Source::DirectiveMap.new(source.comments)
      assert_equal false, directive_map.ignored?(no_method_error(source: source, line: 1))
      assert_equal true, directive_map.ignored?(no_method_error(source: source, line: 3))
      assert_equal false, directive_map.ignored?(no_method_error(source: source, line: 5))

      assert_equal true, directive_map.ignored?(unsupported_syntax_error(source: source, line: 3))
      assert_equal false, directive_map.ignored?(fallback_any_error(source: source, line: 3))
    end
  end

  def test_half_opened_range_ignored?
    with_factory do |factory|
      source = Steep::Source.parse(<<~RUBY, path: Pathname("foo.rb"), factory: factory)
        error
        # steep:ignore all
        error
      RUBY

      directive_map = Steep::Source::DirectiveMap.new(source.comments)
      assert_equal false, directive_map.ignored?(no_method_error(source: source, line: 1))
      assert_equal true, directive_map.ignored?(no_method_error(source: source, line: 3))
    end
  end

  def test_nested_range_ignored?
    with_factory do |factory|
      source = Steep::Source.parse(<<~RUBY, path: Pathname("foo.rb"), factory: factory)
        error
        # steep:ignore NoMethod
        error
        # steep:ignore UnsupportedSyntax
        error
        # steep:ignore end
        error
        # steep:ignore end
        error
      RUBY

      directive_map = Steep::Source::DirectiveMap.new(source.comments)
      assert_equal false, directive_map.ignored?(no_method_error(source: source, line: 1))
      assert_equal true, directive_map.ignored?(no_method_error(source: source, line: 3))
      assert_equal true, directive_map.ignored?(no_method_error(source: source, line: 5))
      assert_equal true, directive_map.ignored?(no_method_error(source: source, line: 7))
      assert_equal false, directive_map.ignored?(no_method_error(source: source, line: 9))

      assert_equal false, directive_map.ignored?(unsupported_syntax_error(source: source, line: 1))
      assert_equal false, directive_map.ignored?(unsupported_syntax_error(source: source, line: 3))
      assert_equal true, directive_map.ignored?(unsupported_syntax_error(source: source, line: 5))
      assert_equal false, directive_map.ignored?(unsupported_syntax_error(source: source, line: 7))
      assert_equal false, directive_map.ignored?(unsupported_syntax_error(source: source, line: 9))
    end
  end
end
