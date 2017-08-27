$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'steep'

require 'minitest/autorun'
require "pp"

module TestHelper
  def assert_any(collection, &block)
    assert collection.any?(&block)
  end

  def refute_any(collection, &block)
    refute collection.any?(&block)
  end

  def parse_signature(signature)
    Steep::Parser.parse_signature(signature)
  end

  def parse_method_type(string)
    Steep::Parser.parse_method(string)
  end
end

module TypeErrorAssertions
  def assert_incompatible_assignment(error, node: nil, lhs_type: nil, rhs_type:)
    assert_instance_of Steep::Errors::IncompatibleAssignment, error

    assert_equal node, error.node if node
    assert_equal lhs_type, error.lhs_type if lhs_type
    assert_equal rhs_type, error.rhs_type if rhs_type

    yield error if block_given?
  end

  def assert_no_method_error(error, node: nil, method: nil, type: nil)
    assert_instance_of Steep::Errors::NoMethod, error

    node and assert_equal node, error.node
    method and assert_equal method, error.method
    type and assert_equal type, error.type

    block_given? and yield error
  end

  def assert_argument_type_mismatch(error, type: nil, method: nil)
    assert_instance_of Steep::Errors::ArgumentTypeMismatch, error

    assert_equal type, error.type if type
    assert_equal method, error.method if method

    yield type, method if block_given?
  end

  def assert_block_type_mismatch(error, expected: nil, actual: nil)
    assert_instance_of Steep::Errors::BlockTypeMismatch, error

    assert_equal expected, error.expected if expected
    assert_equal actual, error.actual if actual

    yield expected, actual if block_given?
  end

  def assert_break_type_mismatch(error, expected: nil, actual: nil)
    assert_instance_of Steep::Errors::BreakTypeMismatch, error

    assert_equal expected, error.expected if expected
    assert_equal actual, error.actual if actual

    yield expected, actual if block_given?
  end
end
