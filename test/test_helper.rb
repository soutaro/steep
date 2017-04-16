$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'steep'

require 'minitest/autorun'

module TypeErrorAssertions
  def assert_invalid_argument_error(error, expected_error: nil, actual_error: nil)
    assert_instance_of Steep::Errors::InvalidArgument, error

    assert_equal expected_error, error.expected if expected_error
    assert_equal actual_error, error.actual if actual_error

    yield error if block_given?
  end

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

  def assert_expected_argument_missing(error, index: nil)
    assert_instance_of Steep::Errors::ExpectedArgumentMissing, error

    index and assert_equal index, error.index

    block_given? and yield error
  end

  def assert_extra_argument_given(error, index: nil)
    assert_instance_of Steep::Errors::ExtraArgumentGiven, error

    assert_equal index, error.index if index

    yield error if block_given?
  end

  def assert_expected_keyword_missing(error, keyword: nil)
    assert_instance_of Steep::Errors::ExpectedKeywordMissing, error

    assert_equal keyword, error.keyword if keyword

    yield error if block_given?
  end

  def assert_extra_keyword_given(error, keyword: nil)
    assert_instance_of Steep::Errors::ExtraKeywordGiven, error

    assert_equal keyword, error.keyword if keyword

    yield keyword if block_given?
  end
end
