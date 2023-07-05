require_relative "../../test_helper"

class AST__Node__TypeAssertionTest < Minitest::Test
  include TestHelper
  include FactoryHelper
  include SubtypingHelper

  def buffer(string)
    buffer = RBS::Buffer.new(name: "foo.rbs", content: string)
    RBS::Location.new(buffer, 0, string.size)
  end

  def test_type
    with_checker do
      loc = buffer(": String")

      assertion = Steep::AST::Node::TypeAssertion.parse(loc)

      assert_equal "String", assertion.type_str
      assert_predicate assertion, :type_syntax?

      type = assertion.type(nil, checker, [])
      assert_equal parse_type("::String"), type
    end
  end

  def test_relative_type
    with_checker(<<~RBS) do
        class Foo
          class Bar
          end
        end
      RBS
      loc = buffer(": Array[Bar]")

      assertion = Steep::AST::Node::TypeAssertion.parse(loc)

      assert_equal "Array[Bar]", assertion.type_str
      assert_predicate assertion, :type_syntax?

      type = assertion.type([nil, TypeName("::Foo")], checker, [])
      assert_equal parse_type("::Array[::Foo::Bar]"), type
    end
  end
end
