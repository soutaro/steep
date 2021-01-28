require_relative 'test_helper'

class ValidationTest < Minitest::Test
  include TestHelper
  include FactoryHelper
  include SubtypingHelper

  Validator = Steep::Signature::Validator
  Diagnostic = Steep::Diagnostic

  def test_validate_constant
    with_checker <<-EOF do |checker|
A: ::Array
    EOF

      validator = Validator.new(checker: checker)
      validator.validate_const

      assert_operator validator, :has_error?
      assert_any validator.each_error do |error|
        error.is_a?(Diagnostic::Signature::InvalidTypeApplication) &&
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
        error.is_a?(Diagnostic::Signature::UnknownTypeName) &&
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
        error.is_a?(Diagnostic::Signature::InvalidTypeApplication) &&
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
        error.is_a?(Diagnostic::Signature::UnknownTypeName) &&
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
        error.is_a?(Diagnostic::Signature::InvalidTypeApplication) &&
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
        error.is_a?(Diagnostic::Signature::UnknownTypeName) &&
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
        error.is_a?(Diagnostic::Signature::InvalidTypeApplication) &&
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

      assert_predicate validator, :has_error?
      assert_any! validator.each_error.to_a, size: 1 do |error|
        assert_instance_of Diagnostic::Signature::UnknownTypeName, error
        assert_equal TypeName("Arraay"), error.name
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
      assert_any! validator.each_error do |error|
        assert_instance_of Diagnostic::Signature::InvalidTypeApplication, error
        assert_equal parse_type("::Array").name, error.name
        assert_empty error.args
        assert_equal [:A], error.params
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
        error.is_a?(Diagnostic::Signature::UnknownTypeName) &&
          error.name == parse_type("Arryay").name
      end
    end
  end

  def test_validate_stdlib
    with_checker with_stdlib: true do |checker|
      validator = Validator.new(checker: checker)

      validator.validate_one_class(RBS::TypeName.new(name: :Hash, namespace: RBS::Namespace.root))
      validator.each_error {|e| e.puts(STDOUT) }

      refute validator.has_error?
    end
  end

  def test_validate_super
    with_checker <<-EOF do |checker|
class Foo < Bar
end
    EOF

      validator = Validator.new(checker: checker)
      validator.validate_decl

      assert_operator validator, :has_error?
      assert_any! validator.each_error do |error|
        assert_instance_of Diagnostic::Signature::UnknownTypeName, error
        assert_equal parse_type("Bar").name, error.name
      end
    end
  end

  def test_validate_mixin
    with_checker <<-EOF do |checker|
class Foo
  include Bar
end
    EOF

      validator = Validator.new(checker: checker)
      validator.validate_decl

      assert_operator validator, :has_error?
      assert_any! validator.each_error do |error|
        assert_instance_of Diagnostic::Signature::UnknownTypeName, error
        assert_equal parse_type("Bar").name, error.name
      end
    end
  end

  def test_outer_namespace
    with_checker <<-EOF do |checker|
class Foo::Bar
end
    EOF

      validator = Validator.new(checker: checker)
      validator.validate

      assert_operator validator, :has_error?
      assert_any! validator.each_error do |error|
        assert_instance_of Diagnostic::Signature::UnknownTypeName, error
        assert_equal parse_type("::Foo").name, error.name
      end
    end

    with_checker <<-EOF do |checker|
type Foo::bar = Integer
    EOF

      validator = Validator.new(checker: checker)
      validator.validate

      assert_operator validator, :has_error?
      assert_any! validator.each_error do |error|
        assert_instance_of Diagnostic::Signature::UnknownTypeName, error
        assert_equal parse_type("::Foo").name, error.name
      end
    end

    with_checker <<-EOF do |checker|
Foo::Bar: Integer
    EOF

      validator = Validator.new(checker: checker)
      validator.validate

      assert_operator validator, :has_error?
      assert_any! validator.each_error do |error|
        assert_instance_of Diagnostic::Signature::UnknownTypeName, error
        assert_equal parse_type("::Foo").name, error.name
      end
    end
  end

  def test_validate_alias_missing
    with_checker <<-EOF do |checker|
interface _Hello
  alias foo bar
end
    EOF

      validator = Validator.new(checker: checker)
      validator.validate_decl

      assert_operator validator, :has_error?
      assert_any! validator.each_error do |error|
        assert_instance_of Diagnostic::Signature::UnknownMethodAlias, error
        assert_equal TypeName("::_Hello"), error.class_name
        assert_equal :bar, error.method_name
        assert_equal "alias foo bar", error.location.source
      end
    end
  end

  def test_duplicated_method_definition
    with_checker <<-EOF do |checker|
class Foo
  def foo: () -> void

  def foo: () -> String
end
    EOF

      validator = Validator.new(checker: checker)
      validator.validate_decl

      assert_operator validator, :has_error?
      assert_any! validator.each_error do |error|
        assert_instance_of Diagnostic::Signature::DuplicatedMethodDefinition, error
        assert_equal TypeName("::Foo"), error.class_name
        assert_equal :foo, error.method_name
      end
    end
  end

  def test_duplicated_interface_method_definition
    with_checker <<-EOF do |checker|
interface _Foo
  def foo: () -> void
end

interface _Bar
  def foo: () -> String
end

class Foo
  include _Foo
  include _Bar
end
    EOF

      validator = Validator.new(checker: checker)
      validator.validate_decl

      assert_operator validator, :has_error?
      assert_any! validator.each_error do |error|
        assert_instance_of Diagnostic::Signature::DuplicatedMethodDefinition, error
        assert_equal TypeName("::Foo"), error.class_name
        assert_equal :foo, error.method_name
      end
    end
  end

  def test_recursive_alias
    with_checker <<-EOF do |checker|
class Foo
  alias foo bar
  alias bar foo
end
    EOF

      validator = Validator.new(checker: checker)
      validator.validate_decl

      assert_operator validator, :has_error?
      assert_any! validator.each_error do |error|
        assert_instance_of Diagnostic::Signature::RecursiveAlias, error
        assert_equal TypeName("::Foo"), error.class_name
        assert_equal Set[:foo, :bar], Set.new(error.names)
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
