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
      RUBY

      SignatureHelpProvider.new(source: source, subtyping: checker).tap do |provider|
        items, index = provider.run(line: 1, column: 14)

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
        TestClass.foo("", 123)
      RUBY

      SignatureHelpProvider.new(source: source, subtyping: checker).tap do |provider|
        items, index = provider.run(line: 1, column: 14)

        assert_equal 0, index
        assert_equal ["(::String, ::Integer) -> ::Array[::Symbol]", "() -> ::Array[::Symbol]"], items.map(&:method_type).map(&:to_s)
      end
    end
  end
end
