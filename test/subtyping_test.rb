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

class Numeric
end

class Integer < Numeric
  def to_int: -> Integer
  def self.sqrt: (Integer) -> Integer
end

class Array[A]
  def `[]`: (Integer) -> A
  def `[]=`: (Integer, A) -> A
  def fetch: (Integer) -> A
end

class Hash[A, B]
  def `[]`: (A) -> B
  def `[]=`: (A, B) -> B
  def keys: -> Array[A]
  def values: -> Array[B]
  def fetch: (A) -> B
end

class Symbol
end

module Kernel : BasicObject
  def Integer: (untyped) -> Integer
end

class TrueClass
end

class FalseClass
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

  def self_type
    AST::Types::Self.new()
  end

  def instance_type
    AST::Types::Instance.new
  end

  def class_type
    AST::Types::Class.new()
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
        instance_type: instance_type,
        class_type: class_type,
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

      assert_success_check checker, "::_A", "::_B"
      assert_success_check checker, "::_B", "::_A"
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
      assert_success_check checker, "::_A", "::_B"
      assert_fail_check checker, "::_B", "::_A" do |result|
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

      assert_fail_check checker, "::_A", "::_B" do |result|
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

      assert_success_check checker, "::_B", "::_A"
      assert_fail_check checker, "::_A", "::_B" do |result|
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
      assert_fail_check checker, "::_B", "::_A" do |result|
        assert_instance_of Failure::PolyMethodSubtyping, result.error
        assert_equal :foo, result.error.name
      end

      assert_success_check checker, "::_A", "::_B"
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

      assert_fail_check checker, "::_A", "::_B" do |result|
        assert_instance_of Failure::UnsatisfiedConstraints, result.error
      end

      assert_fail_check checker, "::_B", "::_A" do |result|
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
      assert_fail_check checker, "::_B", "::_A" do |result|
        assert_instance_of Failure::PolyMethodSubtyping, result.error
      end

      assert_fail_check checker, "::_A", "::_B" do |result|
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
      assert_success_check checker, "::_A", "::_B"
      assert_success_check checker, "::_B", "::_A"
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

      assert_success_check checker, "::_A", "::_B"

      assert_fail_check checker, "::_B", "::_A" do |result|
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

      assert_success_check checker, "::_A", "::_B"

      assert_fail_check checker, "::_B", "::_A" do |result|
        assert_instance_of Failure::UnknownPairError, result.error
      end
    end
  end

  def test_literal
    with_checker do |checker|
      assert_success_check checker, "123", "::Integer"

      assert_fail_check checker, "::Integer", "123" do |result|
        assert_instance_of Failure::UnknownPairError, result.error
      end

      assert_fail_check checker, ":foo", "::Integer" do |result|
        assert_instance_of Failure::UnknownPairError, result.error
      end
    end
  end

  def test_literal_bidirectional
    with_checker do |checker|
      assert_success_check checker, "true", "::TrueClass"
      assert_success_check checker, "::TrueClass", "true"

      assert_success_check checker, "false", "::FalseClass"
      assert_success_check checker, "::FalseClass", "false"
    end
  end

  def test_nil_type
    with_checker do |checker|
      assert_success_check checker, "nil", "::NilClass"
      assert_success_check checker, "::NilClass", "nil"
    end
  end

  def test_void
    with_checker do |checker|
      assert_success_check checker, "void", "void"
      assert_success_check checker, "::Integer", "void"

      assert_fail_check checker, "void", "::String" do |result|
        assert_instance_of Failure::UnknownPairError, result.error
      end
    end
  end

  def print_result(result, output, prefix: "  ")
    mark = result.success? ? "👍" : "🤦"

    buffer = "#{prefix}#{mark} "
    case result
    when Subtyping::Result::Success
      buffer << "(success) #{result.relation}"
      output.puts(buffer)
    when Subtyping::Result::Skip
      buffer << "(skip) #{result.relation}"
      output.puts(buffer)
    when Subtyping::Result::Failure
      buffer << "(#{result.error.message}) #{result.relation}"
      output.puts(buffer)
    when Subtyping::Result::All
      buffer << "(all) #{result.relation} (#{result.branches.size} branches)"
      output.puts(buffer)
      result.branches.each do |b|
        print_result(b, output, prefix: prefix + "  ")
      end
    when Subtyping::Result::Any
      buffer << "(any) #{result.relation} (#{result.branches.size} branches)"
      output.puts(buffer)
      result.branches.each do |b|
        print_result(b, output, prefix: prefix + "  ")
      end
    when Subtyping::Result::Expand
      buffer << "(expand) #{result.relation}"
      output.puts(buffer)
      print_result(result.child, output, prefix: prefix + "  ")
    else
      raise
    end
  end

  def assert_success_check(checker, sub_type, super_type, self_type: parse_type("self", checker: checker), instance_type: parse_type("instance", checker: checker), class_type: parse_type("class", checker: checker), constraints: Constraints.empty)
    self_type = parse_type(self_type, checker: checker) if self_type.is_a?(String)
    instance_type = parse_type(instance_type, checker: checker) if instance_type.is_a?(String)
    class_type = parse_type(class_type, checker: checker) if class_type.is_a?(String)

    relation = parse_relation(sub_type, super_type, checker: checker)
    result = checker.check(
      relation,
      self_type: self_type || :dummy_self_type,
      instance_type: instance_type || :dummy_instance_type,
      class_type: class_type || :dummy_class_type,
      constraints: constraints
    )

    assert_predicate result, :success?, message {
      str = ""
      str << "Expected subtyping check succeed but failed: #{relation.sub_type} <: #{relation.super_type}\n"
      str << "Trace:\n"

      io = StringIO.new()
      print_result(result, io)
      str << io.string
    }
  ensure
    yield result if block_given?
  end

  def assert_fail_check(checker, sub_type, super_type, self_type: nil, instance_type: nil, class_type: nil, constraints: Constraints.empty)
    self_type = parse_type(self_type, checker: checker) if self_type.is_a?(String)
    instance_type = parse_type(instance_type, checker: checker) if instance_type.is_a?(String)
    class_type = parse_type(class_type, checker: checker) if class_type.is_a?(String)

    relation = parse_relation(sub_type, super_type, checker: checker)
    result = checker.check(
      relation,
      self_type: self_type || :dummy_self_type,
      instance_type: instance_type || :dummy_instance_type,
      class_type: class_type || :dummy_class_type,
      constraints: constraints
    )

    assert_predicate result, :failure?, message {
      str = ""
      str << "Expected subtyping check fail but succeeded: #{relation.sub_type} <: #{relation.super_type}\n"
      str << "Trace:\n"
      io = StringIO.new()
      print_result(result, io)
      str << io.string
      str
    }

    yield result.failure_path&.first if block_given?
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
        parse_relation("::Integer", "::Object", checker: checker),
        self_type: AST::Types::Self.new,
        instance_type: AST::Types::Instance.new,
        class_type: AST::Types::Class.new,
        constraints: Subtyping::Constraints.empty
      )

      # Cached because the relation does not have free variables
      assert_operator(
        checker.cache.subtypes,
        :key?,
        [
          parse_relation("::Integer", "::Object", checker: checker),
          AST::Types::Self.new,
          AST::Types::Instance.new,
          AST::Types::Class.new,
          {}
        ]
      )
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

      constraints = Constraints.new(unknowns: [:X])

      assert_success_check(
        checker,
        "::_A",
        parse_type("::_B[X]", checker: checker, variables: [:X]),
        constraints: constraints
      )

      assert_operator constraints, :unknown?, :X
      assert_instance_of AST::Types::Top, constraints.upper_bound(:X)
      assert_equal parse_type("::Integer", checker: checker), constraints.lower_bound(:X)
    end

    with_checker <<-EOS do |checker|
interface _A
  def foo: (Integer) -> void
end

interface _B[A]
  def foo: (A) -> void
end
    EOS

      constraints = Constraints.new(unknowns: [:X])

      assert_success_check(
        checker,
        "::_A",
        parse_type("::_B[X]", checker: checker, variables: [:X]),
        constraints: constraints
      )

      assert_operator constraints, :unknown?, :X
      assert_equal "::Integer", constraints.upper_bound(:X).to_s
      assert_instance_of AST::Types::Bot, constraints.lower_bound(:X)
    end

    with_checker <<-EOS do |checker|
interface _A
  def foo: (Integer) -> Integer
end

interface _B[A]
  def foo: (A) -> A
end
    EOS

      constraints = Constraints.new(unknowns: [:X])
      assert_success_check(
        checker,
        "::_A",
        parse_type("::_B[X]", checker: checker, variables: [:X]),
        constraints: constraints
      )
      assert_operator constraints, :unknown?, :X
      assert_equal "::Integer", constraints.upper_bound(:X).to_s
      assert_equal "::Integer", constraints.lower_bound(:X).to_s
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

      constraints = Constraints.new(unknowns: [:T])
      assert_success_check(
        checker,
        parse_type("::_A[T]", checker: checker, variables: [:T]),
        "::_B",
        constraints: constraints
      )
      assert_equal "::String", constraints.upper_bound(:T).to_s
      assert_equal "::String", constraints.lower_bound(:T).to_s

      variance = Subtyping::VariableVariance.new(covariants: Set[:T], contravariants: Set[:T])
      s = constraints.solution(
        checker,
        variance: variance,
        variables: Set[:T],
        self_type: parse_type("self", checker: checker),
        instance_type: parse_type("instance", checker: checker),
        class_type: parse_type("class", checker: checker)
      )
      assert_equal "::String", s[:T].to_s
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
      assert_fail_check checker, "{ foo: ::String }", "{ foo: ::Integer }"
      assert_success_check checker, "{ foo: ::String, bar: ::Integer }", "{ foo: ::String, bar: ::Integer? }"
      assert_success_check checker, "{ foo: ::String, bar: nil }", "{ foo: ::String, bar: ::Integer? }"
      assert_success_check checker, "{ foo: ::String }", "{ foo: ::String, bar: ::Integer? }"
      assert_fail_check checker, "{ foo: ::String, bar: ::Symbol }", "{ foo: ::String, bar: ::Integer? }"

      constraints = Constraints.new(unknowns: [:X])
      assert_success_check(
        checker,
        "{ foo: ::Integer }",
        parse_type("{ foo: X }", checker: checker, variables: [:X]),
        constraints: constraints
      )
      assert_operator constraints, :unknown?, :X
      assert_equal parse_type("top", checker: checker), constraints.upper_bound(:X)
      assert_equal "::Integer", constraints.lower_bound(:X).to_s

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
      # assert_success_check checker, "::String", "::Object"
      # assert_success_check checker, "::String", "::Kernel"
      # assert_success_check checker, "::String", "::BasicObject"

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

      Constraints.new(unknowns: [:X]).tap do |constraints|
        assert_success_check(
          checker,
          "::Collection[::String]",
          parse_type("::Collection[X]", checker: checker, variables: [:X]),
          constraints: constraints
        )
        assert_operator constraints, :unknown?, :X
        assert_instance_of AST::Types::Top, constraints.upper_bound(:X)
        assert_equal parse_type("::String", checker: checker), constraints.lower_bound(:X)
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

  def test_logic_type
    with_checker do |checker|
      type = AST::Types::Logic::ReceiverIsNil.new()
      assert_success_check checker, type, "true"
      assert_success_check checker, type, "false"
      assert_success_check checker, type, "::TrueClass"
      assert_success_check checker, type, "::FalseClass"
    end
  end

  def test_proc_type
    with_checker do |checker|
      assert_success_check checker, "^() { () -> void } -> void", "^() { () -> void } -> void"
      assert_success_check checker, "^() { (::String) -> ::Object } -> void", "^() { (::Object) -> ::String } -> void"

      assert_fail_check checker, "^() { (::Object) -> void } -> void", "^() { (::String) -> void } -> void"
      assert_fail_check checker, "^() { () -> ::String } -> void", "^() { () -> ::Object } -> void"
    end
  end

  def test_self_type
    with_checker do |checker|
      assert_success_check checker, "self", "::Integer", self_type: "::Integer"
      assert_success_check checker, "self", "::Object", self_type: "::Integer"
      assert_fail_check checker, "self", "::String", self_type: "::Integer"

      assert_fail_check checker, "::Integer", "self", self_type: "::Integer"
      assert_fail_check checker, "::String", "self", self_type: "::Integer"
      assert_fail_check checker, "::Object", "self", self_type: "::Integer"
    end
  end

  def test_instance_type
    with_checker do |checker|
      assert_success_check checker, "instance", "::Integer", instance_type: "::Integer"
      assert_success_check checker, "instance", "::Object", instance_type: "::Integer"
      assert_fail_check checker, "instance", "::String", instance_type: "::Integer"

      assert_success_check checker, "::Integer", "instance", instance_type: "::Integer"
      assert_fail_check checker, "::String", "instance", instance_type: "::Integer"
      assert_fail_check checker, "::Object", "instance", instance_type: "::Integer"
    end
  end

  def test_class_type
    with_checker do |checker|
      assert_success_check checker, "class", "singleton(::Integer)", class_type: "singleton(::Integer)"
      assert_success_check checker, "class", "singleton(::Object)", class_type: "singleton(::Integer)"
      assert_fail_check checker, "class", "singleton(::String)", class_type: "singleton(::Integer)"

      assert_success_check checker, "singleton(::Integer)", "class", class_type: "singleton(::Integer)"
      assert_fail_check checker, "singleton(::Object)", "class", class_type: "singleton(::Integer)"
    end
  end

  def type_params(checker, **params)
    params.map do |name, upper_bound|
      upper_bound = parse_type(upper_bound, checker: checker) if upper_bound.is_a?(String)

      Interface::TypeParam.new(
        name: name,
        upper_bound: upper_bound,
        variance: :invariant,
        unchecked: false
      )
    end
  end

  def test_type_var_bounded
    with_checker do |checker|
      checker.push_variable_bounds(type_params(checker, X: "::String")) do
        assert_success_check checker, AST::Types::Var.new(name: :X), "::String"

        assert_fail_check checker, AST::Types::Var.new(name: :X), "::Integer"
        assert_fail_check checker, "::String", AST::Types::Var.new(name: :X)
      end
    end
  end

  def test_method_type_bounded
    with_checker <<~RBS do |checker|
      interface _A
        def f: [X < Numeric] (X) -> X
      end

      interface _B
        def f: (Integer) -> Integer
      end

      interface _C
        def f: (String) -> String
      end
    RBS

      assert_success_check(checker, "::_A", "::_B")

      assert_fail_check checker, "::_B", "::_A" do |result|
        assert_instance_of Failure::PolyMethodSubtyping, result.error
        assert_equal :f, result.error.name
      end

      assert_fail_check checker, "::_A", "::_C" do |result|
        assert_instance_of Failure::UnsatisfiedConstraints, result.error

        assert_match /X\(\d+\)/, result.error.var.to_s
        assert_equal parse_type("::String", checker: checker), result.error.sub_type
        assert_equal parse_type("::Numeric & ::String", checker: checker), result.error.super_type
      end

      assert_fail_check checker, "::_C", "::_A" do |result|
        assert_instance_of Failure::PolyMethodSubtyping, result.error
        assert_equal :f, result.error.name
      end
    end
  end

  def test_method_type_bounded_2
    with_checker <<~RBS do |checker|
      interface _A
        def f: [X < Numeric] (X) -> X
      end

      interface _B
        def f: [X < Integer] (Numeric) -> X
      end
    RBS

      assert_success_check(checker, "::_B", "::_A")

      assert_fail_check(checker, "::_A", "::_B") do |result|
        assert_instance_of Failure::UnknownPairError, result.error
      end
    end
  end

  def test_cache
    with_checker do |checker|
      checker.push_variable_bounds({ X: parse_type("::Integer", checker: checker) }) do
        assert_success_check(checker, AST::Types::Var.new(name: :X), "::Object")
      end

      checker.push_variable_bounds({ X: parse_type("::BasicObject", checker: checker) }) do
        assert_fail_check(checker, AST::Types::Var.new(name: :X), "::Object")
      end
    end
  end
end
