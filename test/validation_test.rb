require_relative 'test_helper'

class ValidationTest < Minitest::Test
  include TestHelper
  include FactoryHelper
  include SubtypingHelper

  Validator = Steep::Signature::Validator
  Errors = Steep::Signature::Errors

  def test_validate_constant
    with_checker <<-EOF do |checker|
A: ::Array
    EOF

      validator = Validator.new(checker: checker)
      validator.validate_const

      assert_operator validator, :has_error?
      assert_any validator.each_error do |error|
        error.is_a?(Errors::InvalidTypeApplicationError) &&
          error.name == parse_type("::Array").name &&
          error.args == [] &&
          error.params == [:A]
      end
    end

    with_checker <<-EOF do |checker|
A: ::No::Such::Type
    EOF

      validator = Validator.new(checker: checker)
      validator.validate_const

      assert_operator validator, :has_error?
      assert_any validator.each_error do |error|
        error.is_a?(Errors::UnknownTypeNameError) &&
          error.name == parse_type("::No::Such::Type").name
      end
    end
  end

  def test_validate_global
    with_checker <<-EOF do |checker|
$A: Array
    EOF

      validator = Validator.new(checker: checker)
      validator.validate_global

      assert_operator validator, :has_error?
      assert_any validator.each_error do |error|
        error.is_a?(Errors::InvalidTypeApplicationError) &&
          error.name == parse_type("::Array").name &&
          error.args == [] &&
          error.params == [:A]
      end
    end

    with_checker <<-EOF do |checker|
$A: ::No::Such::Type
    EOF

      validator = Validator.new(checker: checker)
      validator.validate_global

      assert_operator validator, :has_error?
      assert_any validator.each_error do |error|
        error.is_a?(Errors::UnknownTypeNameError) &&
          error.name == parse_type("::No::Such::Type").name
      end
    end
  end

  def test_validate_alias
    with_checker <<-EOF do |checker|
type a = Array
    EOF

      validator = Validator.new(checker: checker)
      validator.validate_alias

      assert_operator validator, :has_error?
      assert_any validator.each_error do |error|
        error.is_a?(Errors::InvalidTypeApplicationError) &&
          error.name == parse_type("::Array").name &&
          error.args == [] &&
          error.params == [:A]
      end
    end

    with_checker <<-EOF do |checker|
type a = X::Y::Z
    EOF

      validator = Validator.new(checker: checker)
      validator.validate_alias

      assert_operator validator, :has_error?
      assert_any validator.each_error do |error|
        error.is_a?(Errors::UnknownTypeNameError) &&
          error.name == parse_type("::X::Y::Z").name
      end
    end
  end

  def test_validate_interface
    with_checker <<-EOF do |checker|
interface _Hello[A]
  def foo: -> Array[A, Integer]
end
    EOF

      validator = Validator.new(checker: checker)
      validator.validate_decl

      assert_operator validator, :has_error?
      assert_any validator.each_error do |error|
        error.is_a?(Errors::InvalidTypeApplicationError) &&
          error.name == parse_type("::Array").name &&
          error.args == [parse_type("A", variables: [:A]), parse_type("::Integer")] &&
          error.params == [:A]
      end
    end

    with_checker <<-EOF do |checker|
interface _Hello[A]
  def foo: -> Arraay[A, Integer]
end
    EOF

      validator = Validator.new(checker: checker)
      validator.validate_decl

      assert_operator validator, :has_error?
      assert_any validator.each_error do |error|
        error.is_a?(Errors::UnknownTypeNameError) &&
          error.name == parse_type("::Arraay").name
      end
    end
  end

  def test_validate_class
    with_checker <<-EOF do |checker|
class Foo
  def foo: -> Array
end
    EOF

      validator = Validator.new(checker: checker)
      validator.validate_decl

      assert_operator validator, :has_error?
      assert_any validator.each_error do |error|
        error.is_a?(Errors::InvalidTypeApplicationError) &&
          error.name == parse_type("::Array").name &&
          error.args == [] &&
          error.params == [:A]
      end
    end

    with_checker <<-EOF do |checker|
class Foo
  def foo: -> Arryay
end
    EOF

      validator = Validator.new(checker: checker)
      validator.validate_decl

      assert_operator validator, :has_error?
      assert_any validator.each_error do |error|
        error.is_a?(Errors::UnknownTypeNameError) &&
          error.name == parse_type("::Arryay").name
      end
    end

    with_checker <<-EOF do |checker|
class Foo
  def to_s: -> Integer
end
    EOF

      validator = Validator.new(checker: checker)
      validator.validate_decl

      assert_operator validator, :has_error?
      assert_any validator.each_error do |error|
        error.is_a?(Errors::NoSubtypingInheritanceError) &&
          error.type == parse_type("::Foo") &&
          error.super_type == parse_type("::Object")
      end
    end

    with_checker <<-EOF do |checker|
class Foo
  def self.to_s: -> Integer
end
    EOF

      validator = Validator.new(checker: checker)
      validator.validate_decl

      assert_operator validator, :has_error?
      assert_any validator.each_error do |error|
        error.is_a?(Errors::NoSubtypingInheritanceError) &&
          error.type == parse_type("singleton(::Foo)") &&
          error.super_type == parse_type("singleton(::Object)")
      end
    end
  end

  def test_validate_module
    skip "Not implemented yet"
  end

  def test_validate_instance_variables
    skip "Not implemented yet"
  end
end
