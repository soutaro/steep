require_relative "test_helper"

class ErrorsTest < Minitest::Test
  include TestHelper

  Diagnostic = Steep::Diagnostic
  Errors = Steep::Errors

  def setup
    @node = Parser::Ruby27.parse("2 + 2", "foo.rb")
  end

  def test_to_s_with_message
    assert_equal "foo.rb:1:0: IncompatibleAssignment: lhs_type=lhs, rhs_type=rhs",
                 Diagnostic::Ruby::IncompatibleAssignment.new(node: @node, lhs_type: "lhs", rhs_type: "rhs", result: nil).to_s
  end

  def test_to_s_without_message
    assert_equal "foo.rb:1:0: UnexpectedJump",
                 Errors::UnexpectedJump.new(node: @node).to_s
  end

  def test_to_s_with_class_name
    assert_equal "foo.rb:1:0: NoMethodError: type=String, method=bar",
                 Errors::NoMethod.new(node: @node, type: "String", method: "bar").to_s
  end

  def test_to_s_multiline
    assert_equal "foo.rb:1:0: UnexpectedError: RuntimeError\n>> Oops!\n",
                 Errors::UnexpectedError.new(node: @node, error: RuntimeError.new("Oops!")).to_s
  end
end

