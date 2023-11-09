require_relative "../test_helper"

class Source__DirectiveCommentTest < Minitest::Test
  include FactoryHelper

  def test_valid?
    with_factory do |factory|
      source = Steep::Source.parse(<<~RUBY, path: Pathname("foo.rb"), factory: factory)
        # steep:ignore all
        # steep:ignore end
        # steep:ignore NoMethod
        # steep:ignore NoMethod, UnknownConstant
        # steep:invalid
      RUBY

      comment = Steep::Source::DirectiveComment.new(source.find_comment(line: 1, column: 1))
      assert_equal true, comment.valid?

      comment = Steep::Source::DirectiveComment.new(source.find_comment(line: 2, column: 1))
      assert_equal true, comment.valid?

      comment = Steep::Source::DirectiveComment.new(source.find_comment(line: 3, column: 1))
      assert_equal true, comment.valid?

      comment = Steep::Source::DirectiveComment.new(source.find_comment(line: 4, column: 1))
      assert_equal true, comment.valid?

      comment = Steep::Source::DirectiveComment.new(source.find_comment(line: 5, column: 1))
      assert_equal false, comment.valid?
    end
  end

  def test_all?
    with_factory do |factory|
      source = Steep::Source.parse(<<~RUBY, path: Pathname("foo.rb"), factory: factory)
        # steep:ignore all
        # steep:ignore end
        # steep:ignore NoMethod
        # steep:ignore NoMethod, UnknownConstant
        # steep:invalid
      RUBY

      comment = Steep::Source::DirectiveComment.new(source.find_comment(line: 1, column: 1))
      assert_equal true, comment.all?

      comment = Steep::Source::DirectiveComment.new(source.find_comment(line: 2, column: 1))
      assert_equal false, comment.all?

      comment = Steep::Source::DirectiveComment.new(source.find_comment(line: 3, column: 1))
      assert_equal false, comment.all?

      comment = Steep::Source::DirectiveComment.new(source.find_comment(line: 4, column: 1))
      assert_equal false, comment.all?

      comment = Steep::Source::DirectiveComment.new(source.find_comment(line: 5, column: 1))
      assert_equal false, comment.all?
    end
  end

  def test_start?
    with_factory do |factory|
      source = Steep::Source.parse(<<~RUBY, path: Pathname("foo.rb"), factory: factory)
        # steep:ignore all
        # steep:ignore end
        # steep:ignore NoMethod
        # steep:ignore NoMethod, UnknownConstant
        # steep:invalid
      RUBY

      comment = Steep::Source::DirectiveComment.new(source.find_comment(line: 1, column: 1))
      assert_equal true, comment.start?

      comment = Steep::Source::DirectiveComment.new(source.find_comment(line: 2, column: 1))
      assert_equal false, comment.start?

      comment = Steep::Source::DirectiveComment.new(source.find_comment(line: 3, column: 1))
      assert_equal true, comment.start?

      comment = Steep::Source::DirectiveComment.new(source.find_comment(line: 4, column: 1))
      assert_equal true, comment.start?

      comment = Steep::Source::DirectiveComment.new(source.find_comment(line: 5, column: 1))
      assert_equal true, comment.start?
    end
  end

  def test_end?
    with_factory do |factory|
      source = Steep::Source.parse(<<~RUBY, path: Pathname("foo.rb"), factory: factory)
        # steep:ignore all
        # steep:ignore end
        # steep:ignore NoMethod
        # steep:ignore NoMethod, UnknownConstant
        # steep:invalid
      RUBY

      comment = Steep::Source::DirectiveComment.new(source.find_comment(line: 1, column: 1))
      assert_equal false, comment.end?

      comment = Steep::Source::DirectiveComment.new(source.find_comment(line: 2, column: 1))
      assert_equal true, comment.end?

      comment = Steep::Source::DirectiveComment.new(source.find_comment(line: 3, column: 1))
      assert_equal false, comment.end?

      comment = Steep::Source::DirectiveComment.new(source.find_comment(line: 4, column: 1))
      assert_equal false, comment.end?

      comment = Steep::Source::DirectiveComment.new(source.find_comment(line: 5, column: 1))
      assert_equal false, comment.end?
    end
  end

  def test_diagnostic_names
    with_factory do |factory|
      source = Steep::Source.parse(<<~RUBY, path: Pathname("foo.rb"), factory: factory)
        # steep:ignore all
        # steep:ignore end
        # steep:ignore NoMethod
        # steep:ignore NoMethod, UnknownConstant
        # steep:invalid
      RUBY

      comment = Steep::Source::DirectiveComment.new(source.find_comment(line: 1, column: 1))
      assert_equal [], comment.diagnostic_names

      comment = Steep::Source::DirectiveComment.new(source.find_comment(line: 2, column: 1))
      assert_equal [], comment.diagnostic_names

      comment = Steep::Source::DirectiveComment.new(source.find_comment(line: 3, column: 1))
      assert_equal %w[NoMethod], comment.diagnostic_names

      comment = Steep::Source::DirectiveComment.new(source.find_comment(line: 4, column: 1))
      assert_equal %w[NoMethod UnknownConstant], comment.diagnostic_names

      comment = Steep::Source::DirectiveComment.new(source.find_comment(line: 5, column: 1))
      assert_equal [], comment.diagnostic_names
    end
  end
end
