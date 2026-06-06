require_relative "test_helper"

class TypeNameReferencesTest < Minitest::Test
  include TestHelper
  include FactoryHelper
  include SubtypingHelper
  include TypeConstructionHelper

  TypeNameReferences = Steep::TypeNameReferences

  def collect(checker, source)
    with_standard_construction(checker, source) do |construction, typing|
      construction.synthesize(source.node)
      TypeNameReferences.from_source_file(typing: typing, source: source)
    end
  end

  def test_collects_inferred_types
    with_checker do |checker|
      source = parse_ruby(<<-RUBY)
x = 1
y = x + 2
      RUBY

      names = collect(checker, source)

      assert_includes names, RBS::TypeName.parse("::Integer")
    end
  end

  def test_collects_annotation_only_types
    # `::String` appears only in the annotation; `s` is never used so it never
    # shows up as an inferred node type. It must still be collected.
    with_checker do |checker|
      source = parse_ruby(<<-RUBY)
# @type var s: ::String
x = 1
      RUBY

      names = collect(checker, source)

      assert_includes names, RBS::TypeName.parse("::String")
    end
  end

  def test_collects_method_call_argument_types
    # `::Integer` is the *parameter* type of the called method and never appears
    # as an inferred node type; it is reachable only through the method type.
    with_checker(<<-RBS) do |checker|
class WithParam
  def take: (::Symbol) -> void
end
    RBS
      source = parse_ruby(<<-RUBY)
x = WithParam.new
x.take(:foo)
      RUBY

      names = collect(checker, source)

      assert_includes names, RBS::TypeName.parse("::WithParam")
      assert_includes names, RBS::TypeName.parse("::Symbol")
    end
  end

  def test_collects_type_assertion_types
    # The asserted type of a `#:` assertion is recorded in the typing. `::Symbol`
    # appears nowhere else, so it can only be collected via the assertion.
    with_checker do |checker|
      source = parse_ruby(<<-RUBY)
xs = [] #: Array[::Symbol]
      RUBY

      names = collect(checker, source)

      assert_includes names, RBS::TypeName.parse("::Array")
      assert_includes names, RBS::TypeName.parse("::Symbol")
    end
  end

  def test_collects_type_application_types
    # The type arguments of a `#$` application are recorded in the typing.
    # `::Numeric` appears only in the application.
    with_checker(<<-RBS) do |checker|
class Array[unchecked out Elem]
  def union: [T] (*Array[T]) -> Array[Elem | T]
end
    RBS
      source = parse_ruby(<<-RUBY)
xs = [1].union([1.2]) #$ Numeric
      RUBY

      names = collect(checker, source)

      assert_includes names, RBS::TypeName.parse("::Numeric")
    end
  end

  def test_collects_implements_annotation
    # `::Marker` appears only in `@implements`, never as a constant or call in
    # the source, so collecting it can only be the annotation handling. (The
    # `< Marker` ancestor lives in RBS, which is not a source of references.)
    with_checker(<<-RBS) do |checker|
class Marker
end

class Host < Marker
end
    RBS
      source = parse_ruby(<<-RUBY)
class Host
  # @implements Marker
  def foo
  end
end
      RUBY

      names = collect(checker, source)

      assert_includes names, RBS::TypeName.parse("::Marker")
    end
  end

  def test_collects_nested_class_types_as_absolute
    # A type named relatively inside a nested namespace must be collected as its
    # absolute name. Asserting the specific absolute names are present (rather
    # than only "all names are absolute", which an empty set would satisfy)
    # checks both that extraction works and that names are absolutized.
    with_checker(<<-RBS) do |checker|
module Outer
  class Inner
    def value: () -> Outer::Item
  end

  class Item
  end
end
    RBS
      source = parse_ruby(<<-RUBY)
Outer::Inner.new.value
      RUBY

      names = collect(checker, source)

      refute_empty names
      assert_includes names, RBS::TypeName.parse("::Outer::Inner")
      assert_includes names, RBS::TypeName.parse("::Outer::Item")
      assert names.all?(&:absolute?), "expected all collected names to be absolute: #{names.map(&:to_s)}"
    end
  end
end
