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

type b = no_such_type
    EOF

      validator = Validator.new(checker: checker)
      validator.validate_alias

      assert_operator validator, :has_error?

      assert_any! validator.each_error do |error|
        assert_instance_of Diagnostic::Signature::UnknownTypeName, error
        assert_equal RBS::TypeName.parse("::X::Y::Z"), error.name
      end

      assert_any! validator.each_error do |error|
        assert_instance_of Diagnostic::Signature::UnknownTypeName, error
        assert_equal RBS::TypeName.parse("::no_such_type"), error.name
      end
    end
  end

  def test_generic_alias
    with_checker <<-EOF do |checker|
type list[T] = [T, list[T] | nil]
             | nil
    EOF

      validator = Validator.new(checker: checker)
      validator.validate_alias

      refute_operator validator, :has_error?
    end

    with_checker <<-EOF do |checker|
type broken[T] = Array[broken[Array[T]]]
    EOF

      validator = Validator.new(checker: checker)
      validator.validate_alias

      assert_operator validator, :has_error?
      assert_any!(validator.each_error, size: 1) do |error|
        assert_instance_of Diagnostic::Signature::NonregularTypeAlias, error
        assert_equal RBS::TypeName.parse("::broken"), error.type_name
        assert_equal parse_type("::broken[::Array[T]]", variables: [:T]), error.nonregular_type
      end
    end

    with_checker <<-EOF do |checker|
type broken[T] = broken[Array[T]]
    EOF

      validator = Validator.new(checker: checker)
      validator.validate_alias

      assert_operator validator, :has_error?
      assert_any! validator.each_error, size: 1 do |error|
        assert_instance_of Diagnostic::Signature::RecursiveTypeAlias, error
        assert_equal [RBS::TypeName.parse("::broken")], error.alias_names
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
        assert_equal RBS::TypeName.parse("Arraay"), error.name
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
        assert_equal RBS::TypeName.parse("::_Hello"), error.class_name
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
        assert_equal RBS::TypeName.parse("::Foo"), error.class_name
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
        assert_equal RBS::TypeName.parse("::Foo"), error.class_name
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
        assert_equal RBS::TypeName.parse("::Foo"), error.class_name
        assert_equal Set[:foo, :bar], Set.new(error.names)
      end
    end
  end

  def test_validate_mixin_class
    with_checker <<-EOF do |checker|
interface _FooEach[A]
  def each: () { (A) -> void } -> void
end

module Enum[A] : _FooEach[A]
  def count: () -> Integer
end

class A
  include Enum[Integer]

  def each: () { (Integer) -> void } -> void
end

class B
  include Enum[Integer]
end

class C
  include Enum[Integer]

  def each: () { (String, Integer) -> void } -> void
end

class D
  extend Enum[D]

  def self.each: () { (D) -> void } -> Array[D]
end

class E
  extend Enum[String]
end
    EOF

      Validator.new(checker: checker).tap do |validator|
        validator.validate_one_class(RBS::TypeName.parse("::A"))

        assert_predicate validator, :no_error?
      end

      Validator.new(checker: checker).tap do |validator|
        validator.validate_one_class(RBS::TypeName.parse("::B"))

        assert_predicate validator, :has_error?
        assert_any!(validator.each_error, size: 1) do |error|
          assert_instance_of Diagnostic::Signature::ModuleSelfTypeError, error
        end
      end

      Validator.new(checker: checker).tap do |validator|
        validator.validate_one_class(RBS::TypeName.parse("::C"))

        assert_predicate validator, :has_error?
        assert_any!(validator.each_error, size: 1) do |error|
          assert_instance_of Diagnostic::Signature::ModuleSelfTypeError, error
        end
      end

      Validator.new(checker: checker).tap do |validator|
        validator.validate_one_class(RBS::TypeName.parse("::D"))

        assert_predicate validator, :no_error?
      end

      Validator.new(checker: checker).tap do |validator|
        validator.validate_one_class(RBS::TypeName.parse("::E"))

        assert_predicate validator, :has_error?
        assert_any!(validator.each_error, size: 1) do |error|
          assert_instance_of Diagnostic::Signature::ModuleSelfTypeError, error
        end
      end
    end
  end

  def test_validate_mixin_module
    with_checker <<-EOF do |checker|
interface _FooEach[A]
  def each: () { (A) -> void } -> void
end

module Enum[A] : _FooEach[A]
  def count: () -> Integer
end

module ArrayExt[A] : Array[A]
end

module A
  include Enum[String]

  def each: () { (String) -> void } -> void
end

module B : Array[String]
  include ArrayExt[String]
end

module C
  include ArrayExt[Integer]
end
    EOF

      Validator.new(checker: checker).tap do |validator|
        validator.validate_one_class(RBS::TypeName.parse("::A"))

        assert_predicate validator, :no_error?
      end

      Validator.new(checker: checker).tap do |validator|
        validator.validate_one_class(RBS::TypeName.parse("::B"))

        assert_predicate validator, :no_error?
      end

      Validator.new(checker: checker).tap do |validator|
        validator.validate_one_class(RBS::TypeName.parse("::C"))

        assert_predicate validator, :has_error?
        assert_any!(validator.each_error, size: 1) do |error|
          assert_instance_of Diagnostic::Signature::ModuleSelfTypeError, error
        end
      end
    end
  end

  def test_validate_instance_variables
    with_checker <<-EOF do |checker|
class A
  @foo: Integer
end

class B < A
  @foo: Integer?
end

module M[A]
  @bar: A
end

class C[X]
  include M[Array[X]]

  @bar: X
end

class D
  extend M[String]

  self.@bar: Array[String]
end
EOF
      Validator.new(checker: checker).tap do |validator|
        validator.validate_one_class(RBS::TypeName.parse("::A"))

        assert_predicate validator, :no_error?
      end

      Validator.new(checker: checker).tap do |validator|
        validator.validate_one_class(RBS::TypeName.parse("::B"))

        assert_predicate validator, :has_error?
        assert_any!(validator.each_error, size: 1) do |error|
          assert_instance_of Diagnostic::Signature::InstanceVariableTypeError, error
        end
      end

      Validator.new(checker: checker).tap do |validator|
        validator.validate_one_class(RBS::TypeName.parse("::C"))

        assert_predicate validator, :has_error?
        assert_any!(validator.each_error, size: 1) do |error|
          assert_instance_of Diagnostic::Signature::InstanceVariableTypeError, error
        end
      end

      Validator.new(checker: checker).tap do |validator|
        validator.validate_one_class(RBS::TypeName.parse("::D"))

        assert_predicate validator, :has_error?
        assert_any!(validator.each_error, size: 1) do |error|
          assert_instance_of Diagnostic::Signature::InstanceVariableTypeError, error
        end
      end
    end
  end

  def test_validate_class_variables
    with_checker <<-EOF do |checker|
class A
  @@foo: Integer
end

class B < A
  @@foo: Integer?
end

class C < B
end
    EOF
      Validator.new(checker: checker).tap do |validator|
        validator.validate_one_class(RBS::TypeName.parse("::A"))

        assert_predicate validator, :no_error?
      end

      Validator.new(checker: checker).tap do |validator|
        validator.validate_one_class(RBS::TypeName.parse("::C"))

        assert_predicate validator, :no_error?
      end

      Validator.new(checker: checker).tap do |validator|
        validator.validate_one_class(RBS::TypeName.parse("::B"))

        assert_predicate validator, :has_error?
        assert_any!(validator.each_error, size: 1) do |error|
          assert_instance_of Diagnostic::Signature::ClassVariableDuplicationError, error
        end
      end
    end
  end

  def test_validate_type_application
    with_checker <<-EOF do |checker|
class Foo[X < Numeric]
end

interface _Bar[X < Module]
end

type baz[T < Object] = T
    EOF
      Validator.new(checker: checker).tap do |validator|
        validator.validate_type(factory.type_1(parse_type("::Foo[::Integer]")))
        assert_predicate validator, :no_error?
      end

      Validator.new(checker: checker).tap do |validator|
        validator.validate_type(factory.type_1(parse_type("::Foo[::String]")))
        refute_predicate validator, :no_error?
        assert_any!(validator.each_error, size: 1) do |error|
          assert_instance_of Diagnostic::Signature::UnsatisfiableTypeApplication, error
        end
      end

      Validator.new(checker: checker).tap do |validator|
        validator.validate_type(factory.type_1(parse_type("::_Bar[singleton(::Integer)]")))
        assert_predicate validator, :no_error?
      end

      Validator.new(checker: checker).tap do |validator|
        validator.validate_type(factory.type_1(parse_type("::_Bar[::String]")))
        refute_predicate validator, :no_error?
        assert_any!(validator.each_error, size: 1) do |error|
          assert_instance_of Diagnostic::Signature::UnsatisfiableTypeApplication, error
        end
      end

      Validator.new(checker: checker).tap do |validator|
        validator.validate_type(factory.type_1(parse_type("::baz[singleton(::Integer)]")))
        assert_predicate validator, :no_error?
      end

      Validator.new(checker: checker).tap do |validator|
        validator.validate_type(factory.type_1(parse_type("::baz[::BasicObject]")))
        refute_predicate validator, :no_error?
        assert_any!(validator.each_error, size: 1) do |error|
          assert_instance_of Diagnostic::Signature::UnsatisfiableTypeApplication, error
        end
      end
    end
  end

  def test_validate_type_application_class_decl
    with_checker <<-EOF do |checker|
type x[A < Numeric] = A

class Foo[X < Integer]
  def f: () -> x[X]
end

class Bar[X0 < String]
  def f: () -> Array[x[X0]]
end
    EOF

      Validator.new(checker: checker).tap do |validator|
        validator.validate_one_class(RBS::TypeName.parse("::Foo"))
        assert_predicate validator, :no_error?
      end

      Validator.new(checker: checker).tap do |validator|
        validator.validate_one_class(RBS::TypeName.parse("::Bar"))
        refute_predicate validator, :no_error?

        assert_any!(validator.each_error, size: 1) do |error|
          assert_instance_of Diagnostic::Signature::UnsatisfiableTypeApplication, error
          assert_equal "Type application of `::x` doesn't satisfy the constraints: X0 <: ::Numeric", error.header_line
          assert_equal "x[X0]", error.location.source
        end
      end
    end
  end

  def test_validate_type_application_super
    with_checker <<RBS do |checker|
class Base[X < Numeric]
end

class C0 < Base[Integer]
end

class C1 < Base[String]
end

class D0[X < Integer] < Base[X]
end

class D1[X < Object] < Base[X]
end
RBS

      Validator.new(checker: checker).tap do |validator|
        validator.validate_one_class(RBS::TypeName.parse("::Base"))
        assert_predicate validator, :no_error?
      end

      Validator.new(checker: checker).tap do |validator|
        validator.validate_one_class(RBS::TypeName.parse("::C0"))
        assert_predicate validator, :no_error?
      end

      Validator.new(checker: checker).tap do |validator|
        validator.validate_one_class(RBS::TypeName.parse("::C1"))
        refute_predicate validator, :no_error?

        assert_any!(validator.each_error, size: 1) do |error|
          assert_instance_of Diagnostic::Signature::UnsatisfiableTypeApplication, error
          assert_equal "Type application of `::Base` doesn't satisfy the constraints: ::String <: ::Numeric", error.header_line
          assert_equal "Base[String]", error.location.source
        end
      end

      Validator.new(checker: checker).tap do |validator|
        validator.validate_one_class(RBS::TypeName.parse("::D0"))
        assert_predicate validator, :no_error?
      end

      Validator.new(checker: checker).tap do |validator|
        validator.validate_one_class(RBS::TypeName.parse("::D1"))
        refute_predicate validator, :no_error?

        assert_any!(validator.each_error, size: 1) do |error|
          assert_instance_of Diagnostic::Signature::UnsatisfiableTypeApplication, error
          assert_equal "Type application of `::Base` doesn't satisfy the constraints: X <: ::Numeric", error.header_line
          assert_equal "Base[X]", error.location.source
        end
      end
    end
  end

  def test_validate_type_application_module_self
    with_checker <<RBS do |checker|
class Base[X < Numeric]
end

module M1 : Base[Integer]
end

module M2 : Base[String]
end

module M3[X < Integer] : Base[X]
end

module M4[X < String] : Base[X]
end
RBS

      Validator.new(checker: checker).tap do |validator|
        validator.validate_one_class(RBS::TypeName.parse("::Base"))
        assert_predicate validator, :no_error?
      end

      Validator.new(checker: checker).tap do |validator|
        validator.validate_one_class(RBS::TypeName.parse("::M1"))
        assert_predicate validator, :no_error?
      end

      Validator.new(checker: checker).tap do |validator|
        validator.validate_one_class(RBS::TypeName.parse("::M2"))
        refute_predicate validator, :no_error?

        assert_any!(validator.each_error, size: 1) do |error|
          assert_instance_of Diagnostic::Signature::UnsatisfiableTypeApplication, error
          assert_equal "Type application of `::Base` doesn't satisfy the constraints: ::String <: ::Numeric", error.header_line
          assert_equal "Base[String]", error.location.source
        end
      end

      Validator.new(checker: checker).tap do |validator|
        validator.validate_one_class(RBS::TypeName.parse("::M3"))
        assert_predicate validator, :no_error?
      end

      Validator.new(checker: checker).tap do |validator|
        validator.validate_one_class(RBS::TypeName.parse("::M4"))
        refute_predicate validator, :no_error?

        assert_any!(validator.each_error, size: 1) do |error|
          assert_instance_of Diagnostic::Signature::UnsatisfiableTypeApplication, error
          assert_equal "Type application of `::Base` doesn't satisfy the constraints: X <: ::Numeric", error.header_line
          assert_equal "Base[X]", error.location.source
        end
      end
    end
  end

  def test_validate_type_application_mixin
    with_checker <<RBS do |checker|
module M[X < Numeric]
end

module N[X < Numeric]
end

interface _I[X < Numeric]
end

class C0
  include M[Integer]

  include _I[Integer]

  extend N[Integer]

  include _I[Integer]
end

class C1
  include M[String]

  include _I[String]

  extend N[String]

  extend _I[String]
end

class D0[X < Integer]
  include M[X]

  include _I[X]
end

class D1[X < Object]
  include M[X]

  include _I[X]
end
RBS

      Validator.new(checker: checker).tap do |validator|
        validator.validate_one_class(RBS::TypeName.parse("::M"))
        assert_predicate validator, :no_error?
      end

      Validator.new(checker: checker).tap do |validator|
        validator.validate_one_class(RBS::TypeName.parse("::N"))
        assert_predicate validator, :no_error?
      end

      Validator.new(checker: checker).tap do |validator|
        validator.validate_one_class(RBS::TypeName.parse("::C0"))
        assert_predicate validator, :no_error?
      end

      Validator.new(checker: checker).tap do |validator|
        validator.validate_one_class(RBS::TypeName.parse("::C1"))
        refute_predicate validator, :no_error?

        assert_any!(validator.each_error, size: 4) do |error|
          assert_instance_of Diagnostic::Signature::UnsatisfiableTypeApplication, error
          assert_equal "Type application of `::M` doesn't satisfy the constraints: ::String <: ::Numeric", error.header_line
          assert_equal "include M[String]", error.location.source
        end

        assert_any!(validator.each_error, size: 4) do |error|
          assert_instance_of Diagnostic::Signature::UnsatisfiableTypeApplication, error
          assert_equal "Type application of `::_I` doesn't satisfy the constraints: ::String <: ::Numeric", error.header_line
          assert_equal "include _I[String]", error.location.source
        end

        assert_any!(validator.each_error, size: 4) do |error|
          assert_instance_of Diagnostic::Signature::UnsatisfiableTypeApplication, error
          assert_equal "Type application of `::N` doesn't satisfy the constraints: ::String <: ::Numeric", error.header_line
          assert_equal "extend N[String]", error.location.source
        end

        assert_any!(validator.each_error, size: 4) do |error|
          assert_instance_of Diagnostic::Signature::UnsatisfiableTypeApplication, error
          assert_equal "Type application of `::_I` doesn't satisfy the constraints: ::String <: ::Numeric", error.header_line
          assert_equal "extend _I[String]", error.location.source
        end
      end

      Validator.new(checker: checker).tap do |validator|
        validator.validate_one_class(RBS::TypeName.parse("::D0"))
        assert_predicate validator, :no_error?
      end

      Validator.new(checker: checker).tap do |validator|
        validator.validate_one_class(RBS::TypeName.parse("::D1"))
        refute_predicate validator, :no_error?

        assert_any!(validator.each_error, size: 2) do |error|
          assert_instance_of Diagnostic::Signature::UnsatisfiableTypeApplication, error
          assert_equal "Type application of `::M` doesn't satisfy the constraints: X <: ::Numeric", error.header_line
          assert_equal "include M[X]", error.location.source
        end

        assert_any!(validator.each_error, size: 2) do |error|
          assert_instance_of Diagnostic::Signature::UnsatisfiableTypeApplication, error
          assert_equal "Type application of `::_I` doesn't satisfy the constraints: X <: ::Numeric", error.header_line
          assert_equal "include _I[X]", error.location.source
        end
      end
    end
  end

  def test_validate_type_application_interface
    with_checker <<RBS do |checker|
interface _A[X < Numeric]
end

interface _I0
  include _A[Integer]
end

interface _I1
  include _A[String]
end

interface _J0[X < Integer]
  include _A[X]
end

interface _J1[X < Object]
  include _A[X]
end
RBS

      Validator.new(checker: checker).tap do |validator|
        validator.validate_one_interface(RBS::TypeName.parse("::_A"))
        assert_predicate validator, :no_error?
      end

      Validator.new(checker: checker).tap do |validator|
        validator.validate_one_interface(RBS::TypeName.parse("::_I0"))
        assert_predicate validator, :no_error?
      end

      Validator.new(checker: checker).tap do |validator|
        validator.validate_one_interface(RBS::TypeName.parse("::_I1"))
        refute_predicate validator, :no_error?

        assert_any!(validator.each_error, size: 1) do |error|
          assert_instance_of Diagnostic::Signature::UnsatisfiableTypeApplication, error
          assert_equal "Type application of `::_A` doesn't satisfy the constraints: ::String <: ::Numeric", error.header_line
          assert_equal "include _A[String]", error.location.source
        end
      end

      Validator.new(checker: checker).tap do |validator|
        validator.validate_one_interface(RBS::TypeName.parse("::_J0"))
        assert_predicate validator, :no_error?
      end

      Validator.new(checker: checker).tap do |validator|
        validator.validate_one_interface(RBS::TypeName.parse("::_J1"))
        refute_predicate validator, :no_error?

        assert_any!(validator.each_error, size: 1) do |error|
          assert_instance_of Diagnostic::Signature::UnsatisfiableTypeApplication, error
          assert_equal "Type application of `::_A` doesn't satisfy the constraints: X <: ::Numeric", error.header_line
          assert_equal "include _A[X]", error.location.source
        end
      end
    end
  end

  def test_validate_type_application_method
    with_checker <<-EOF do |checker|
type x[A < Numeric] = A

interface _Foo
  def f: [X < Integer] () -> x[X]
end

interface _Bar
  def f: [X < String] () -> x[X]
end
    EOF

      Validator.new(checker: checker).tap do |validator|
        validator.validate_one_interface(RBS::TypeName.parse("::_Foo"))
        assert_predicate validator, :no_error?
      end

      Validator.new(checker: checker).tap do |validator|
        validator.validate_one_interface(RBS::TypeName.parse("::_Bar"))
        refute_predicate validator, :no_error?

        assert_any!(validator.each_error, size: 1) do |error|
          assert_instance_of Diagnostic::Signature::UnsatisfiableTypeApplication, error
          assert_equal "Type application of `::x` doesn't satisfy the constraints: X <: ::Numeric", error.header_line
          assert_equal "x[X]", error.location.source
        end
      end
    end
  end

  def test_validate_type_application_interface_decl
    with_checker <<-EOF do |checker|
type x[A < Numeric] = A

interface _Foo[X < Integer]
  def f: () -> x[X]
end

interface _Bar[X < String]
  def f: () -> x[X]
end
    EOF

      Validator.new(checker: checker).tap do |validator|
        validator.validate_one_interface(RBS::TypeName.parse("::_Foo"))
        assert_predicate validator, :no_error?
      end

      Validator.new(checker: checker).tap do |validator|
        validator.validate_one_interface(RBS::TypeName.parse("::_Bar"))
        refute_predicate validator, :no_error?

        assert_any!(validator.each_error, size: 1) do |error|
          assert_instance_of Diagnostic::Signature::UnsatisfiableTypeApplication, error
          assert_equal "Type application of `::x` doesn't satisfy the constraints: X <: ::Numeric", error.header_line
          assert_equal "x[X]", error.location.source
        end
      end
    end
  end

  def test_validate_type_application_alias_decl
    with_checker <<-EOF do |checker|
type x[A < Numeric] = A

type foo[X < Integer] = x[X]

type bar[X < String] = x[X]
    EOF

      Validator.new(checker: checker).tap do |validator|
        validator.validate_one_alias(RBS::TypeName.parse("::foo"))
        assert_predicate validator, :no_error?
      end

      Validator.new(checker: checker).tap do |validator|
        validator.validate_one_alias(RBS::TypeName.parse("::bar"))
        refute_predicate validator, :no_error?

        assert_any!(validator.each_error, size: 1) do |error|
          assert_instance_of Diagnostic::Signature::UnsatisfiableTypeApplication, error
          assert_equal "Type application of `::x` doesn't satisfy the constraints: X <: ::Numeric", error.header_line
          assert_equal "x[X]", error.location.source
        end
      end
    end
  end

  def test_validate_generic_declaration_dependents
    with_checker <<-RBS do |checker|
interface _MinimalSet[S]
  def +: (S) -> S
end

class ArraySet
  def +: (ArraySet) -> ArraySet
end

class SetValueExtractor[S < _MinimalSet[S]]
end

Test: SetValueExtractor[ArraySet]
    RBS

      Validator.new(checker: checker).tap do |validator|
        validator.validate_const
        assert_predicate validator, :no_error?
      end
    end
  end

  def test_generic_ancestor_argument_types
    with_checker <<~RBS do |checker|
        interface _X[T]
        end

        class Y
          include _X[Array]
        end
      RBS

      Validator.new(checker: checker).tap do |validator|
        validator.validate

        assert_any!(validator.each_error, size: 1) do |error|
          assert_instance_of Diagnostic::Signature::InvalidTypeApplication, error
          assert_equal "Type `::Array` is generic but used as a non generic type", error.header_line
          assert_equal "Array", error.location.source
        end
      end
    end
  end

  def test_validate_type_alias_module_alias
    with_checker <<~RBS do |checker|
        module Foo
          type t = Integer
        end

        module Bar = Foo

        type baz = Bar::t
      RBS

      Validator.new(checker: checker).tap do |validator|
        validator.validate
        assert_predicate validator, :no_error?
      end
    end
  end

  def test_validate_type_app__classish_bounded
    with_checker <<~RBS do |checker|
        interface _Generic[T < Object]
        end

        class Foo < BasicObject
          class User
            type t1 = _Generic[instance]
            type t2 = _Generic[class]

            include _Generic[class]
            extend _Generic[instance]
          end
        end
      RBS

      Validator.new(checker: checker).tap do |validator|
        validator.validate
        assert_predicate validator.each_error.to_a, :empty?
      end
    end
  end

  def test_validate_type__generics_default_ref
    with_checker <<~RBS do |checker|
        module A[A_A, A_B = A_A, A_C = A_B]
        end

        class B[B_A, B_B = B_A, B_C = B_B]
        end

        interface _C[C_A, C_B = C_A, C_C = C_B]
        end

        type d[D_A, D_B = D_A, D_C = D_B] = untyped
      RBS

      Validator.new(checker: checker).tap do |validator|
        validator.validate
        refute_predicate validator.each_error.to_a, :empty?

        assert_any!(validator.each_error) do |error|
          assert_instance_of Diagnostic::Signature::TypeParamDefaultReferenceError, error
          assert_equal "The default type of `A_C` cannot depend on optional type parameters", error.header_line
          assert_equal "A_B", error.location.source
        end

        assert_any!(validator.each_error) do |error|
          assert_instance_of Diagnostic::Signature::TypeParamDefaultReferenceError, error
          assert_equal "The default type of `B_C` cannot depend on optional type parameters", error.header_line
          assert_equal "B_B", error.location.source
        end

        assert_any!(validator.each_error) do |error|
          assert_instance_of Diagnostic::Signature::TypeParamDefaultReferenceError, error
          assert_equal "The default type of `C_C` cannot depend on optional type parameters", error.header_line
          assert_equal "C_B", error.location.source
        end

        assert_any!(validator.each_error) do |error|
          assert_instance_of Diagnostic::Signature::TypeParamDefaultReferenceError, error
          assert_equal "The default type of `D_C` cannot depend on optional type parameters", error.header_line
          assert_equal "D_B", error.location.source
        end
      end
    end
  end

  def test_validate_type__generics_default_upperbound
    with_checker <<~RBS do |checker|
        module A[A_A, A_B < String = A_A, A_C < Array[untyped] = Array[A_A]]
        end

        class B[B_A, B_B < String = B_A, B_C < Array[untyped] = Array[B_A]]
        end

        interface _C[C_A, C_B < String = C_A, C_C < Array[untyped] = Array[C_A]]
        end

        type d[D_A, D_B < String = D_A, D_C < Array[untyped] = Array[D_A]] = untyped
      RBS

      Validator.new(checker: checker).tap do |validator|
        validator.validate
        refute_predicate validator.each_error.to_a, :empty?

        assert_any!(validator.each_error) do |error|
          assert_instance_of Diagnostic::Signature::UnsatisfiableGenericsDefaultType, error
          assert_equal "The default type of `A_B` doesn't satisfy upper bound constraint: A_A <: ::String", error.header_line
          assert_equal "A_A", error.location.source
        end

        assert_any!(validator.each_error) do |error|
          assert_instance_of Diagnostic::Signature::UnsatisfiableGenericsDefaultType, error
          assert_equal "The default type of `B_B` doesn't satisfy upper bound constraint: B_A <: ::String", error.header_line
          assert_equal "B_A", error.location.source
        end

        assert_any!(validator.each_error) do |error|
          assert_instance_of Diagnostic::Signature::UnsatisfiableGenericsDefaultType, error
          assert_equal "The default type of `C_B` doesn't satisfy upper bound constraint: C_A <: ::String", error.header_line
          assert_equal "C_A", error.location.source
        end

        assert_any!(validator.each_error) do |error|
          assert_instance_of Diagnostic::Signature::UnsatisfiableGenericsDefaultType, error
          assert_equal "The default type of `D_B` doesn't satisfy upper bound constraint: D_A <: ::String", error.header_line
          assert_equal "D_A", error.location.source
        end
      end
    end
  end

  def test_validate__deprecated__type_name
    skip "Type name resolution for module/class aliases is changed in RBS 3.10/4.0"

    with_checker <<~RBS do |checker|
        %a{deprecated} class Foo end

        %a{deprecated} module Bar end

        %a{deprecated} class Foo1 = Foo

        %a{deprecated} module Bar1 = Bar

        %a{deprecated} type baz = untyped

        class DeprecatedReference
          def foo: () -> Foo
                 | () -> Bar

          def baz: () -> Array[Foo1 | Bar1]

          type t = baz
        end
      RBS

      Validator.new(checker: checker).tap do |validator|
        validator.validate
        assert_predicate validator, :has_error?

        assert_any!(validator.each_error) do |error|
          assert_instance_of Diagnostic::Signature::DeprecatedTypeName, error
          assert_equal "Type `::Foo` is deprecated", error.header_line
        end

        assert_any!(validator.each_error) do |error|
          assert_instance_of Diagnostic::Signature::DeprecatedTypeName, error
          assert_equal "Type `::Bar` is deprecated", error.header_line
        end

        assert_any!(validator.each_error) do |error|
          assert_instance_of Diagnostic::Signature::DeprecatedTypeName, error
          assert_equal "Type `::Foo1` is deprecated", error.header_line
        end

        assert_any!(validator.each_error) do |error|
          assert_instance_of Diagnostic::Signature::DeprecatedTypeName, error
          assert_equal "Type `::Bar1` is deprecated", error.header_line
        end

        assert_any!(validator.each_error) do |error|
          assert_instance_of Diagnostic::Signature::DeprecatedTypeName, error
          assert_equal "Type `::baz` is deprecated", error.header_line
        end
      end
    end
  end

  def test_validate__deprecated__class
    with_checker <<~RBS do |checker|
        %a{deprecated} class Foo end

        %a{deprecated} module M end

        %a{deprecated} interface _Foo end

        class Bar < Foo
          include M
          include _Foo
        end
      RBS

      Validator.new(checker: checker).tap do |validator|
        validator.validate
        assert_predicate validator, :has_error?

        assert_any!(validator.each_error) do |error|
          assert_instance_of Diagnostic::Signature::DeprecatedTypeName, error
          assert_equal "Type `::Foo` is deprecated", error.header_line
        end
        assert_any!(validator.each_error) do |error|
          assert_instance_of Diagnostic::Signature::DeprecatedTypeName, error
          assert_equal "Type `::M` is deprecated", error.header_line
        end
        assert_any!(validator.each_error) do |error|
          assert_instance_of Diagnostic::Signature::DeprecatedTypeName, error
          assert_equal "Type `::_Foo` is deprecated", error.header_line
        end
      end
    end
  end

  def test_validate__deprecated__module
    with_checker <<~RBS do |checker|
        %a{deprecated} class Foo end

        %a{deprecated} module M end

        %a{deprecated} interface _Foo end

        module Bar : Foo, _Foo, M
        end
      RBS

      Validator.new(checker: checker).tap do |validator|
        validator.validate
        assert_predicate validator, :has_error?

        assert_any!(validator.each_error) do |error|
          assert_instance_of Diagnostic::Signature::DeprecatedTypeName, error
          assert_equal "Type `::Foo` is deprecated", error.header_line
        end
        assert_any!(validator.each_error) do |error|
          assert_instance_of Diagnostic::Signature::DeprecatedTypeName, error
          assert_equal "Type `::M` is deprecated", error.header_line
        end
        assert_any!(validator.each_error) do |error|
          assert_instance_of Diagnostic::Signature::DeprecatedTypeName, error
          assert_equal "Type `::_Foo` is deprecated", error.header_line
        end
      end
    end
  end

  def test_validate__deprecated__class_alias
    with_checker <<~RBS do |checker|
        %a{deprecated} class Foo end

        %a{deprecated} module M end

        class Bar = Foo

        module N = M
      RBS

      Validator.new(checker: checker).tap do |validator|
        validator.validate
        assert_predicate validator, :has_error?

        assert_any!(validator.each_error) do |error|
          assert_instance_of Diagnostic::Signature::DeprecatedTypeName, error
          assert_equal "Type `::Foo` is deprecated", error.header_line
        end
        assert_any!(validator.each_error) do |error|
          assert_instance_of Diagnostic::Signature::DeprecatedTypeName, error
          assert_equal "Type `::M` is deprecated", error.header_line
        end
      end
    end
  end

  def test_validate__deprecated__generic
    with_checker <<~RBS do |checker|
        %a{deprecated} class Foo end

        %a{deprecated} module M end

        class Bar[A < Foo, B = M]
        end
      RBS

      Validator.new(checker: checker).tap do |validator|
        validator.validate
        assert_predicate validator, :has_error?

        assert_any!(validator.each_error) do |error|
          assert_instance_of Diagnostic::Signature::DeprecatedTypeName, error
          assert_equal "Type `::Foo` is deprecated", error.header_line
        end
        assert_any!(validator.each_error) do |error|
          assert_instance_of Diagnostic::Signature::DeprecatedTypeName, error
          assert_equal "Type `::M` is deprecated", error.header_line
        end
      end
    end
  end

  def test_validate__deprecated__namespace
    with_checker <<~RBS do |checker|
        %a{deprecated} module M end

        module M
          class Foo
          end
        end
      RBS

      Validator.new(checker: checker).tap do |validator|
        validator.validate
        assert_predicate validator, :has_error?

        assert_any!(validator.each_error) do |error|
          assert_instance_of Diagnostic::Signature::DeprecatedTypeName, error
          assert_equal "Type `::M` is deprecated", error.header_line
        end
      end
    end
  end
end
