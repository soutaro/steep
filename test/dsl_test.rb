# frozen_string_literal: true

require "test_helper"

class DslTest < Minitest::Test
  def setup
    @steepfile_contents = <<~CONTENTS
      signatures "sig"
      signatures "sig-private"
    CONTENTS
  end

  def test_signatures
    dsl = Steep::Dsl.new
    dsl.evaluate_steepfile(@steepfile_contents)

    assert_equal %w[sig sig-private], dsl.instance_variable_get(:@signatures)
  end

  def test_method_missing
    dsl = Steep::Dsl.new

    assert_raises NoMethodError do
      dsl.evaluate_steepfile("some_method 'some_arg'")
    end
  end
end
