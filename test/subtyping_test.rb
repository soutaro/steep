require_relative "test_helper"

class SubtypingTest < Minitest::Test
  include TestHelper
  include Steep

  BUILTIN = <<-EOB
class BasicObject
  def initialize: () -> void
end

class Object < BasicObject
  def class: () -> class
  def tap: { (self) -> untyped } -> self
  def yield_self: [A] { (self) -> A } -> A
  def to_s: -> String
end

class Class
  def new: (*untyped) -> untyped
  def allocate: -> untyped
end

class Module
  def attr_reader: (Symbol) -> nil
end

class String
  def to_str: -> String
  def self.try_convert: (untyped) -> String
end

class Integer
  def to_int: -> Integer
  def self.sqrt: (Integer) -> Integer
end

class Array[A]
  def `[]`: (Integer) -> A
  def `[]=`: (Integer, A) -> A
end

class Hash[A, B]
  def `[]`: (A) -> B
  def `[]=`: (A, B) -> B
  def keys: -> Array[A]
  def values: -> Array[B]
end

class Symbol
end

module Kernel
  def Integer: (untyped) -> Integer
end
  EOB

  include FactoryHelper

  Relation = Subtyping::Relation
  Constraints = Subtyping::Constraints
  Failure = Subtyping::Result::Failure

  def parse_type(string, checker:, variables: [])
    type = RBS::Parser.parse_type(string, variables: variables)
    checker.factory.type(type)
  end

  def parse_method_type(string, checker:, variables: [])
    type = RBS::Parser.parse_method_type(string, variables: variables)
    checker.factory.method_type type
  end

  def parse_relation(sub_type, super_type, checker:)
    Relation.new(
      sub_type: sub_type.is_a?(String) ? parse_type(sub_type, checker: checker) : sub_type,
      super_type: super_type.is_a?(String) ? parse_type(super_type, checker: checker) : super_type
    )
  end

  def with_checker(*files, nostdlib: false, &block)
    paths = {}

    files.each.with_index do |content, index|
      if content.is_a?(Hash)
        paths.merge!(content)
      else
        paths["#{index}.rbs"] = content
      end
    end

    paths["builtin.rbs"] = BUILTIN unless nostdlib
    with_factory(paths, nostdlib: true) do |factory|
      yield Subtyping::Check.new(factory: factory)
    end
  end

  def assert_success_result(result)
    assert_instance_of Subtyping::Result::Success, result
    yield result if block_given?
  end

  def assert_fail_result(result)
    assert_instance_of Subtyping::Result::Failure, result
    yield result if block_given?
  end

  def test_reflexive
    with_checker do |checker|
      type = parse_type("::Integer", checker: checker)

      result = checker.check(
        Relation.new(sub_type: type, super_type: type),
        self_type: parse_type("self", checker: checker),
        constraints: Constraints.empty
      )

      assert_success_result result
    end
  end

  def test_interface
    with_checker <<-EOS do |checker|
interface _A
  def foo: -> Integer
end

interface _B
  def foo: -> untyped
end
    EOS

      assert_success_result checker.check(parse_relation("::_A", "::_B", checker: checker), self_type: parse_type("self", checker: checker), constraints: Constraints.empty)
      assert_success_result checker.check(parse_relation("::_B", "::_A", checker: checker), self_type: parse_type("self", checker: checker), constraints: Constraints.empty)
    end
  end

  def test_interface2
    with_checker <<-EOS do |checker|
interface _A
  def foo: -> Integer
  def bar: -> untyped
end

interface _B
  def foo: -> untyped
end
    EOS
      assert_success_result checker.check(parse_relation("::_A", "::_B", checker: checker), self_type: parse_type("self", checker: checker), constraints: Constraints.empty)
      assert_fail_result checker.check(parse_relation("::_B", "::_A", checker: checker), self_type: parse_type("self", checker: checker), constraints: Constraints.empty) do |result|
        assert_instance_of Failure::MethodMissingError, result.error
        assert_equal :bar, result.error.name
      end
    end
  end

  def test_interface3
    with_checker <<-EOS do |checker|
interface _A
  def foo: -> Integer
end

interface _B
  def foo: -> String
end
    EOS

      assert_fail_result checker.check(parse_relation("::_A", "::_B", checker: checker), self_type: parse_type("self", checker: checker), constraints: Constraints.empty) do |result|
        assert_instance_of Failure::UnknownPairError, result.error
      end
    end
  end

  def test_interface4
    with_checker <<-EOS do |checker|
interface _A
  def foo: () -> Integer
end

interface _B
  def foo: (?Integer, ?foo: Symbol) -> untyped
end
    EOS

      assert_success_result checker.check(parse_relation("::_B", "::_A", checker: checker), self_type: parse_type("self", checker: checker), constraints: Constraints.empty)
      assert_fail_result checker.check(parse_relation("::_A", "::_B", checker: checker), self_type: parse_type("self", checker: checker), constraints: Constraints.empty) do |result|
        assert_instance_of Failure::ParameterMismatchError, result.error
        assert_equal :foo, result.error.name
      end
    end
  end

  def test_interface5
    with_checker(<<-EOS) do |checker|
interface _A
  def foo: [A] () -> A
end

interface _B
  def foo: () -> Integer
end
    EOS
      assert_fail_result checker.check(parse_relation("::_B", "::_A", checker: checker), self_type: parse_type("self", checker: checker), constraints: Constraints.empty) do |result|
        assert_instance_of Failure::PolyMethodSubtyping, result.error
        assert_equal :foo, result.error.name
      end

      assert_success_result checker.check(parse_relation("::_A", "::_B", checker: checker), self_type: parse_type("self", checker: checker), constraints: Constraints.empty)
    end
  end

  def test_interface51
    with_checker <<-EOS do |checker|
interface _A
  def foo: [X] (X) -> X
end

interface _B
  def foo: (String) -> Integer
end
    EOS

      assert_fail_result checker.check(parse_relation("::_A", "::_B", checker: checker), self_type: parse_type("self", checker: checker), constraints: Constraints.empty) do |result|
        assert_instance_of Failure::PolyMethodSubtyping, result.error
        assert_equal :foo, result.error.name
      end

      assert_fail_result checker.check(parse_relation("::_B", "::_A", checker: checker), self_type: parse_type("self", checker: checker), constraints: Constraints.empty) do |result|
        assert_instance_of Failure::PolyMethodSubtyping, result.error
        assert_equal :foo, result.error.name
      end
    end
  end

  def test_interface52
    with_checker <<-EOS do |checker|
interface _A
  def foo: [X] (X) -> Object
end

interface _B
  def foo: (String) -> Integer
end
    EOS
      assert_fail_result checker.check(parse_relation("::_B", "::_A", checker: checker), self_type: parse_type("self", checker: checker), constraints: Constraints.empty) do |result|
        assert_instance_of Failure::PolyMethodSubtyping, result.error
      end

      assert_fail_result checker.check(parse_relation("::_A", "::_B", checker: checker), self_type: parse_type("self", checker: checker), constraints: Constraints.empty) do |result|
        assert_instance_of Failure::UnknownPairError, result.error
      end
    end
  end

  def test_interface53
    with_checker <<-EOS do |checker|
interface _A
  def foo: [X] () -> X
end

interface _B
  def foo: () -> untyped
end
    EOS
      assert_success_check checker, "::_A", "::_B"
      assert_success_check checker, "::_B", "::_A"
    end

    with_checker <<-EOS do |checker|
interface _A
  def foo: [X] () -> X
end

interface _B
  def foo: () -> String
end
    EOS
      assert_success_check checker, "::_A", "::_B"
      assert_fail_check checker, "::_B", "::_A" do |result|
        assert_instance_of Failure::PolyMethodSubtyping, result.error
      end
    end
  end

  def test_interface6
    with_checker <<-EOS do |checker|
interface _A
  def foo: [A, B] (A) -> B
end

interface _B
  def foo: [X, Y] (X) -> Y
end
    EOS
      assert_success_result checker.check(parse_relation("::_A", "::_B", checker: checker), self_type: parse_type("self", checker: checker), constraints: Constraints.empty)
      assert_success_result checker.check(parse_relation("::_B", "::_A", checker: checker), self_type: parse_type("self", checker: checker), constraints: Constraints.empty)
    end
  end

  def test_interface7
    with_checker <<-EOS do |checker|
interface _A
  def foo: (Integer) -> Integer
         | (untyped) -> untyped
end

interface _B
  def foo: (String) -> String
end
    EOS

      assert_success_result checker.check(parse_relation("::_A", "::_B", checker: checker), self_type: parse_type("self", checker: checker), constraints: Constraints.empty)

      assert_fail_result checker.check(parse_relation("::_B", "::_A", checker: checker), self_type: parse_type("self", checker: checker), constraints: Constraints.empty) do |result|
        assert_instance_of Failure::UnknownPairError, result.error
      end
    end
  end

  def test_interface8
    with_checker <<-EOS do |checker|
interface _A
  def foo: () { () -> Object } -> String
end

interface _B
  def foo: () { () -> String } -> Object
end
    EOS

      assert_success_result checker.check(parse_relation("::_A", "::_B", checker: checker), self_type: parse_type("self", checker: checker), constraints: Constraints.empty)

      assert_fail_result checker.check(parse_relation("::_B", "::_A", checker: checker), self_type: parse_type("self", checker: checker), constraints: Constraints.empty) do |result|
        assert_instance_of Failure::UnknownPairError, result.error
      end
    end
  end

  def test_literal
    with_checker do |checker|
      assert_success_result checker.check(parse_relation("123", "::Integer", checker: checker), self_type: parse_type("self", checker: checker), constraints: Constraints.empty)

      assert_fail_result checker.check(parse_relation("::Integer", "123", checker: checker), self_type: parse_type("self", checker: checker), constraints: Constraints.empty) do |result|
        assert_instance_of Failure::UnknownPairError, result.error
      end

      assert_fail_result checker.check(parse_relation(":foo", "::Integer", checker: checker), self_type: parse_type("self", checker: checker), constraints: Constraints.empty) do |result|
        assert_instance_of Failure::UnknownPairError, result.error
      end
    end
  end

  def test_literal_bidirectional
    with_checker do |checker|
      assert_success_result checker.check(parse_relation("true", "::TrueClass", checker: checker), self_type: parse_type("self", checker: checker), constraints: Constraints.empty)
      assert_success_result checker.check(parse_relation("::TrueClass", "true", checker: checker), self_type: parse_type("self", checker: checker), constraints: Constraints.empty)

      assert_success_result checker.check(parse_relation("false", "::FalseClass", checker: checker), self_type: parse_type("self", checker: checker), constraints: Constraints.empty)
      assert_success_result checker.check(parse_relation("::FalseClass", "false", checker: checker), self_type: parse_type("self", checker: checker), constraints: Constraints.empty)
    end
  end

  def test_nil_type
    with_checker do |checker|
      assert_success_result checker.check(parse_relation("nil", "::NilClass", checker: checker), self_type: parse_type("self", checker: checker), constraints: Constraints.empty)
      assert_success_result checker.check(parse_relation("::NilClass", "nil", checker: checker), self_type: parse_type("self", checker: checker), constraints: Constraints.empty)
    end
  end

  def test_void
    with_checker do |checker|
      assert_success_result checker.check(parse_relation("void", "void", checker: checker), self_type: parse_type("self", checker: checker), constraints: Constraints.empty)

      assert_success_result checker.check(parse_relation("::Integer", "void", checker: checker), self_type: parse_type("self", checker: checker), constraints: Constraints.empty)

      assert_fail_result checker.check(parse_relation("void", "::String", checker: checker), self_type: parse_type("self", checker: checker), constraints: Constraints.empty) do |result|
        assert_instance_of Failure::UnknownPairError, result.error
      end
    end
  end

  def assert_success_check(checker, sub_type, super_type, self_type: parse_type("self", checker: checker), constraints: Constraints.empty)
    relation = parse_relation(sub_type, super_type, checker: checker)
    result = checker.check(relation, self_type: self_type, constraints: constraints)

    assert result.instance_of?(Subtyping::Result::Success), message {
      str = ""
      str << "Expected subtyping check succeed but failed: #{relation.sub_type} <: #{relation.super_type}\n"
      str << "Trace:\n"
      result.trace.each do |*xs|
        str << "  #{xs.join(", ")}\n"
      end
      str
    }
    yield result if block_given?
  end

  def assert_fail_check(checker, sub_type, super_type, self_type: parse_type("self", checker: checker), constraints: Constraints.empty)
    relation = parse_relation(sub_type, super_type, checker: checker)
    result = checker.check(relation, self_type: self_type, constraints: constraints)

    assert result.instance_of?(Subtyping::Result::Failure), message {
      str = ""
      str << "Expected subtyping check fail but succeeded: #{relation.sub_type} <: #{relation.super_type}\n"
      if result.respond_to? :trace
        str << "Trace:\n"
        result.trace.each do |*xs|
          str << "  #{xs.join(", ")}\n"
        end
      end
      str
    }
    yield result if block_given?
  end

  def test_union
    with_checker do |checker|
      assert_success_check checker, "::String", "::Object | ::String"

      assert_fail_check checker, "::Object | ::Integer", "::String" do |result|
        assert_instance_of Failure::UnknownPairError, result.error
      end
    end

    with_checker <<-EOS do |checker|
interface _A
  def foo: () -> ::Integer
  def bar: () -> ::String
end

interface _B
  def foo: () -> ::Integer
  def baz: () -> ::Array[untyped]
end

interface _X
  def foo: () -> ::Integer
  def bar: (::String) -> void
  def baz: (::Integer) -> bool
end
    EOS
      assert_fail_check checker, "::_X", "::_A | ::_B" do |result|
        assert_instance_of Failure::ParameterMismatchError, result.error
      end
    end
  end

  def test_intersection
    with_checker do |checker|
      assert_success_check checker, "::String", "::Object & ::String"

      assert_fail_check checker, "::Object", "::Integer & ::String" do |result|
        assert_instance_of Failure::UnknownPairError, result.error
      end

      assert_fail_check checker, "::Object & ::Integer", "::String" do |result|
        assert_instance_of Failure::UnknownPairError, result.error
      end
    end
  end

  def test_caching
    with_checker do |checker|
      checker.check(
        Subtyping::Relation.new(
          sub_type: AST::Types::Name.new_instance(name: :"::Object"),
          super_type: AST::Types::Var.new(name: :foo)
        ),
        self_type: parse_type("self", checker: checker),
        constraints: Subtyping::Constraints.empty
      )

      # Not cached because the relation has free variables
      assert_empty checker.cache
    end

    with_checker do |checker|
      checker.check(
        parse_relation("::Integer", "::Object", checker: checker),
        self_type: parse_type("self", checker: checker),
        constraints: Subtyping::Constraints.empty
      )

      # Cached because the relation does not have free variables
      assert_operator checker.cache,
                      :key?,
                      [parse_relation("::Integer", "::Object", checker: checker), parse_type("self", checker: checker)]
    end
  end

  def test_constraints_01
    with_checker <<-EOS do |checker|
interface _A
  def foo: -> Integer
end

interface _B[A]
  def foo: -> A
end
    EOS

      assert_success_check checker,
                           "::_A",
                           parse_type("::_B[X]", checker: checker, variables: [:X]),
                           constraints: Constraints.new(unknowns: [:X]) do |result|
        assert_operator result.constraints, :unknown?, :X
        assert_instance_of AST::Types::Top, result.constraints.upper_bound(:X)
        assert_equal parse_type("::Integer", checker: checker), result.constraints.lower_bound(:X)
      end
    end

    with_checker <<-EOS do |checker|
interface _A
  def foo: (Integer) -> void
end

interface _B[A]
  def foo: (A) -> void
end
    EOS

      assert_success_check checker,
                           "::_A",
                           parse_type("::_B[X]", checker: checker, variables: [:X]),
                           constraints: Constraints.new(unknowns: [:X]) do |result|
        assert_operator result.constraints, :unknown?, :X
        assert_equal "::Integer", result.constraints.upper_bound(:X).to_s
        assert_instance_of AST::Types::Bot, result.constraints.lower_bound(:X)
      end
    end

    with_checker <<-EOS do |checker|
interface _A
  def foo: (Integer) -> Integer
end

interface _B[A]
  def foo: (A) -> A
end
    EOS

      assert_success_check checker,
                           "::_A",
                           parse_type("::_B[X]", checker: checker, variables: [:X]),
                           constraints: Constraints.new(unknowns: [:X]) do |result|
        assert_operator result.constraints, :unknown?, :X
        assert_equal "::Integer", result.constraints.upper_bound(:X).to_s
        assert_equal "::Integer", result.constraints.lower_bound(:X).to_s
      end
    end
  end

  def test_constraints2
    with_checker <<-EOS do |checker|
interface _A[X]
  def get: -> X
  def set: (X) -> self
end

interface _B
  def get: -> String
  def set: (String) -> self
end
    EOS

      assert_success_check checker,
                           parse_type("::_A[T]", checker: checker, variables: [:T]),
                           "::_B",
                           constraints: Constraints.new(unknowns: [:T]) do |result|
        assert_equal "::String", result.constraints.upper_bound(:T).to_s
        assert_equal "::String", result.constraints.lower_bound(:T).to_s

        variance = Subtyping::VariableVariance.new(covariants: Set[:T], contravariants: Set[:T])
        s = result.constraints.solution(checker, variance: variance, variables: Set[:T], self_type: parse_type("self", checker: checker))
        assert_equal "::String", s[:T].to_s
      end
    end
  end

  def test_tuple_subtyping
    with_checker do |checker|
      assert_success_check checker, "[::Integer, ::String]", "::Array[::Integer | ::String]"
      assert_success_check checker, "[1, 2, 3]", "::Array[::Integer]"
      assert_success_check checker, "[::Integer, ::String]", "::String | ::Array[untyped]"
      assert_success_check checker, "[::Integer, ::String]", "[untyped, untyped]"
      assert_success_check checker, "[1, 2, 3]", "[::Integer, ::Integer, ::Integer]"
    end
  end

  def test_expand_alias
    with_checker <<-EOS do |checker|
type foo = String | Integer
    EOS
      assert_success_check checker, "::String", "::foo"
      assert_success_check checker, "::Integer", "::foo"
      assert_fail_check checker, "bool", "::foo"
    end

    with_checker <<-EOS do |checker|
type json = String | Integer | Array[json] | Hash[String, json]
    EOS
      assert_success_check checker, "::String", "::json"
      assert_success_check checker, "::Integer", "::json"

      # Hash[String, Array[json]] <: json doesn't hold.
      # Because json !<: Array[json], which is required by Hash type application.
      assert_fail_check checker, "::Hash[::String, ::Array[::json]]", "::json"
    end
  end

  def test_hash
    with_checker do |checker|
      assert_success_check checker, "{ foo: ::Integer, bar: ::String }", "{ foo: ::Integer }"

      assert_success_check checker,
                           "{ foo: ::Integer }",
                           parse_type("{ foo: X }", checker: checker, variables: [:X]),
                           constraints: Constraints.new(unknowns: [:X]) do |result|
        assert_operator result.constraints, :unknown?, :X
        assert_equal "::Integer", result.constraints.upper_bound(:X).to_s
        assert_equal "::Integer", result.constraints.lower_bound(:X).to_s
      end

      assert_success_check checker, "{ foo: ::Integer, bar: bool }", "::Hash[:foo | :bar, ::Integer | bool]"
    end
  end

  def test_self
    with_checker <<-EOF do |checker|
interface _ToS
  def to_s: () -> String
end
    EOF
      assert_success_check checker, "^(::_ToS) -> void", "^(self) -> untyped", self_type: parse_type("::Integer", checker: checker)
    end
  end

  def test_integer_rational
    with_checker <<-EOF, nostdlib: true do |checker|
class BasicObject
end

class Object < BasicObject
end

interface _Int
  def clamp: [A] () -> (self | A)
end

interface _Ratio
  def clamp: [A] () -> (self | A)
end
    EOF

      assert_success_check checker, "::_Int", "::_Ratio"
    end
  end

  def test_instance_super_types
    with_checker <<-EOF do |checker|
class Object
  include Kernel
end

interface _Hashing
end

class SuperString < String
  include _Hashing
end

module Foo[X, Y]
end

class Set[X] < Array[X]
  include Foo[String, X]
end
    EOF

      parse_type("::Object", checker: checker).tap do |type|
        super_types = checker.instance_super_types(type.name, args: type.args)

        assert_equal [
                       parse_type("::BasicObject", checker: checker),
                       parse_type("::Kernel", checker: checker)
                     ], super_types
      end

      parse_type("::SuperString", checker: checker).tap do |type|
        super_types = checker.instance_super_types(type.name, args: type.args)

        assert_equal [
                       parse_type("::String", checker: checker),
                       parse_type("::_Hashing", checker: checker)
                     ], super_types
      end

      parse_type("::Set[::String]", checker: checker).tap do |type|
        super_types = checker.instance_super_types(type.name, args: type.args)

        assert_equal [
                       parse_type("::Array[::String]", checker: checker),
                       parse_type("::Foo[::String, ::String]", checker: checker)
                     ], super_types
      end
    end
  end

  def test_singleton_super_types
    with_checker <<-EOF do |checker|
class Object
  include Kernel
end

class SuperString < String
  include _Hashing
  extend Foo[String, Integer]
end

module Foo[X, Y]
end
    EOF

      parse_type("singleton(::Object)", checker: checker).tap do |type|
        super_types = checker.singleton_super_types(type.name)

        assert_equal [
                       parse_type("singleton(::BasicObject)", checker: checker)
                     ], super_types
      end

      parse_type("singleton(::SuperString)", checker: checker).tap do |type|
        super_types = checker.singleton_super_types(type.name)

        assert_equal [
                       parse_type("singleton(::String)", checker: checker),
                       parse_type("::Foo[::String, ::Integer]", checker: checker)
                     ], super_types
      end
    end
  end

  def test_nominal_typing
    with_checker <<-EOF do |checker|
class Object
  include Kernel
end

class String
  def to_s: (Integer) -> String
end
    EOF
      assert_success_check checker, "::String", "::Object"
      assert_success_check checker, "::String", "::Kernel"
      assert_success_check checker, "::String", "::BasicObject"

      assert_fail_check checker, "::Object", "::String" do |result|
        assert_instance_of Failure::UnknownPairError, result.error
      end
    end
  end

  def test_nominal_typing2
    with_checker <<-EOF do |checker|
class Collection[out X]
  def get: () -> X
end

class SuperCollection[out X] < Collection[X]
end
    EOF
      assert_success_check checker, "::Collection[::String]", "::Object"
      assert_success_check checker, "::Collection[::String]", "::Collection[::Object]"
      assert_fail_check checker, "::Collection[::Object]", "::Collection[::String]"

      assert_success_check(checker,
                           "::Collection[::String]",
                           parse_type("::Collection[X]", checker: checker, variables: [:X]),
                           constraints: Constraints.new(unknowns: [:X])) do |result|
        assert_operator result.constraints, :unknown?, :X
        assert_instance_of AST::Types::Top, result.constraints.upper_bound(:X)
        assert_equal parse_type("::String", checker: checker), result.constraints.lower_bound(:X)
      end

      assert_success_check checker, "::SuperCollection[::String]", "::Collection[::String]"
      assert_success_check checker, "::SuperCollection[::String]", "::Collection[::Object]"
    end
  end

  def test_literal_alias_union
    with_checker <<-EOF do |checker|
type a = 1 | 2 | 3
type b = "x" | "y" | "z"

type c = a | b
    EOF
      assert_success_check checker, "1", "::a"
      assert_success_check checker, '"x"', "::b"

      assert_success_check checker, "1", "::c"
      assert_success_check checker, '"z"', "::c"
    end
  end
end
