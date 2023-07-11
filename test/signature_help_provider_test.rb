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
      end
    end
  end
end
