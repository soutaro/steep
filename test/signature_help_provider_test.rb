require_relative "test_helper"

class SignatureHelpProviderTest < Minitest::Test
  include TestHelper
  include FactoryHelper
  include SubtypingHelper

  include Steep
  SignatureHelpProvider = Services::SignatureHelpProvider

  def test_send_error
    with_checker(<<~RBS) do
        class TestClass
          def self.foo: (String, Integer) -> Array[Symbol]
        end
      RBS
      source = Source.parse(<<~RUBY, path: Pathname("a.rb"), factory: checker.factory)
        TestClass.foo()
        TestClass&.foo()
      RUBY

      SignatureHelpProvider.new(source: source, subtyping: checker).tap do |provider|
        items, index = provider.run(line: 1, column: 14)
        assert_nil index
        assert_equal ["(::String, ::Integer) -> ::Array[::Symbol]"], items.map(&:method_type).map(&:to_s)

        items, index = provider.run(line: 2, column: 15)
        assert_nil index
        assert_equal ["(::String, ::Integer) -> ::Array[::Symbol]"], items.map(&:method_type).map(&:to_s)
      end
    end
  end

  def test_send_ok
    with_checker(<<~RBS) do
        class TestClass
          def self.foo: (String, Integer) -> Array[Symbol]
                      | () -> Array[Symbol]
        end
      RBS
      source = Source.parse(<<~RUBY, path: Pathname("a.rb"), factory: checker.factory)
        # Show signature help for a commented method call
        TestClass.foo("", 123)
        TestClass&.foo("", 123)
      RUBY

      SignatureHelpProvider.new(source: source, subtyping: checker).tap do |provider|
        items, index = provider.run(line: 2, column: 14)
        assert_equal 0, index
        assert_equal ["(::String, ::Integer) -> ::Array[::Symbol]", "() -> ::Array[::Symbol]"], items.map(&:method_type).map(&:to_s)

        items, index = provider.run(line: 3, column: 15)
        assert_equal 0, index
        assert_equal ["(::String, ::Integer) -> ::Array[::Symbol]", "() -> ::Array[::Symbol]"], items.map(&:method_type).map(&:to_s)
      end
    end
  end

  def test_active_parameter
    with_checker(<<~RBS) do
        class TestClass
          def self.foo: (String, Integer, *String, kw1: String, kw2: Integer, **String) -> void
        end
      RBS
      source = Source.parse(<<~RUBY, path: Pathname("a.rb"), factory: checker.factory)
        TestClass.foo("", 123, "", "", kw1: "", kw2: 456, kw3: "", kw4: "", **kwargs)
        #   5   10   15   20   25   30   35   40   45   50   55   60   65   70   75
      RUBY

      SignatureHelpProvider.new(source: source, subtyping: checker).tap do |provider|
        items, index = provider.run(line: 1, column: 14)
        assert_equal 0, items.first.active_parameter

        items, index = provider.run(line: 1, column: 18)
        assert_equal 1, items.first.active_parameter

        items, index = provider.run(line: 1, column: 23)
        assert_equal 2, items.first.active_parameter

        items, index = provider.run(line: 1, column: 27)
        assert_equal 2, items.first.active_parameter

        items, index = provider.run(line: 1, column: 31)
        assert_equal 3, items.first.active_parameter

        items, index = provider.run(line: 1, column: 40)
        assert_equal 4, items.first.active_parameter

        items, index = provider.run(line: 1, column: 50)
        assert_equal 5, items.first.active_parameter

        items, index = provider.run(line: 1, column: 59)
        assert_equal 5, items.first.active_parameter

        items, index = provider.run(line: 1, column: 68)
        assert_equal 5, items.first.active_parameter
      end
    end
  end

  def test_active_parameter_in_typing
    with_checker(<<~RBS) do
        class TestClass
          def self.foo: (String, Integer, *String, kw1: String, kw2: Integer, **String) -> void
        end
      RBS
      source = Source.parse(<<~RUBY, path: Pathname("a.rb"), factory: checker.factory)
        TestClass.foo()
        TestClass.foo("",)
        TestClass.foo("", "",)
        TestClass.foo("", "", "",)
        TestClass.foo("", "", "", "",)
        TestClass.foo("", "", "", "", *args,)
        TestClass.foo("", "", "", "", *args, kw1: true,)
        TestClass.foo("", "", "", "", *args, kw2: true,)
        TestClass.foo("", "", "", "", *args, kw3: true,)
        TestClass.foo("", "", "", "", *args, kw1: true, **kwargs,)
        #   5   10   15   20   25   30   35   40   45   50   55   60   65   70   75
      RUBY

      SignatureHelpProvider.new(source: source, subtyping: checker).tap do |provider|
        items, index = provider.run(line: 1, column: 14)
        assert_equal 0, items.first.active_parameter

        items, index = provider.run(line: 2, column: 17)
        assert_equal 1, items.first.active_parameter

        items, index = provider.run(line: 3, column: 21)
        assert_equal 2, items.first.active_parameter

        items, index = provider.run(line: 4, column: 25)
        assert_equal 2, items.first.active_parameter

        items, index = provider.run(line: 5, column: 29)
        assert_equal 2, items.first.active_parameter

        items, index = provider.run(line: 6, column: 36)
        assert_equal 3, items.first.active_parameter

        items, index = provider.run(line: 7, column: 47)
        assert_equal 4, items.first.active_parameter

        items, index = provider.run(line: 8, column: 47)
        assert_equal 5, items.first.active_parameter

        items, index = provider.run(line: 9, column: 47)
        assert_equal 5, items.first.active_parameter

        items, index = provider.run(line: 10, column: 57)
        assert_equal 5, items.first.active_parameter
      end
    end
  end

  def test_send__with_block
    with_checker(<<~RBS) do
      RBS
      source = Source.parse(<<~RUBY, path: Pathname("a.rb"), factory: checker.factory)
        [1].each() do |x|

        end
      RUBY

      SignatureHelpProvider.new(source: source, subtyping: checker).tap do |provider|
        items, index = provider.run(line: 1, column: 9)
        assert_equal 0, index
        assert_equal ["() { (::Integer) -> untyped } -> ::Array[::Integer]"], items.map(&:method_type).map(&:to_s)

        assert_nil provider.run(line: 2, column: 0)
      end
    end
  end

  def test_send__within_block
    with_checker(<<~RBS) do
      RBS
      source = Source.parse(<<~RUBY, path: Pathname("a.rb"), factory: checker.factory)
        [1].each() do |x|
          x.zero?()
        end
      RUBY

      SignatureHelpProvider.new(source: source, subtyping: checker).tap do |provider|
        items, index = provider.run(line: 2, column: 10)
        assert_equal 0, index
        assert_equal ["() -> bool"], items.map(&:method_type).map(&:to_s)
      end
    end
  end

  def test_send__within_block_error
    with_checker(<<~RBS) do
      RBS
      source = Source.parse(<<~RUBY, path: Pathname("a.rb"), factory: checker.factory)
        [1].each() do |x|
          x.aaaaa()
        end
      RUBY

      SignatureHelpProvider.new(source: source, subtyping: checker).tap do |provider|
        assert_nil provider.run(line: 2, column: 10)
      end
    end
  end
end
