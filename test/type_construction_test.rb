require_relative "test_helper"

class TypeConstructionTest < Minitest::Test
  include TestHelper
  include TypeErrorAssertions
  include FactoryHelper
  include SubtypingHelper
  include TypeConstructionHelper

  Namespace = RBS::Namespace

  Diagnostic = Steep::Diagnostic
  Typing = Steep::Typing
  ConstantEnv = Steep::TypeInference::ConstantEnv
  TypeEnv = Steep::TypeInference::TypeEnv
  TypeConstruction = Steep::TypeConstruction
  Annotation = Steep::AST::Annotation
  Context = Steep::TypeInference::Context
  AST = Steep::AST
  MethodCall = Steep::TypeInference::MethodCall

  DEFAULT_SIGS = <<-EOS
interface _A
  def `+`: (_A) -> _A
end

interface _B
end

interface _C
  def f: () -> _A
  def g: (_A, ?_B) -> _B
  def h: (a: _A, ?b: _B) -> _C
end

interface _D
  def foo: () -> untyped
end

interface _X
  def f: () { (_A) -> _D } -> _C
end

interface _Kernel
  def foo: (_A) -> _B
         | (_C) -> _D
end

interface _PolyMethod
  def snd: [A] (untyped, A) -> A
  def try: [A] { (untyped) -> A } -> A
end

module Foo[A]
end
  EOS

  def with_checker(*files, no_default: false, &block)
    unless no_default
      files << DEFAULT_SIGS
    end

    super(*files, &block)
  end

  def test_lvar_with_annotation
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
# @type var x: _A
x = (_ = nil)
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal parse_type("untyped"), typing.type_of(node: source.node)
        assert_empty typing.errors
      end
    end
  end

  def test_lvar_with_annotation_type_check
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
# @type var x: _B
# @type var z: _A
x = (_ = nil)
z = x
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal parse_type("::_B"), typing.type_of(node: source.node)

        assert_typing_error(typing, size: 1) do |errors|
          errors[0].tap do |error|
            assert_instance_of Diagnostic::Ruby::IncompatibleAssignment, error
            assert_equal parse_type("::_A"), error.lhs_type
            assert_equal parse_type("::_B"), error.rhs_type
            assert_equal :lvasgn, error.node.type
            assert_equal :z, error.node.children[0]
          end
        end
      end
    end
  end

  def test_lvar_without_annotation_infer
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
x = 1
z = x
      EOF

      with_standard_construction(checker, source, cursor: [1, 0]) do |construction, typing|
        pair = construction.synthesize(source.node)

        assert_equal parse_type("::Integer"), typing.type_of(node: source.node)

        assert_nil typing.cursor_context.context.type_env[:x]
        assert_nil typing.cursor_context.context.type_env[:z]

        assert_empty typing.errors
      end

      with_standard_construction(checker, source, cursor: [1, 5]) do |construction, typing|
        pair = construction.synthesize(source.node)

        assert_equal parse_type("::Integer"), typing.type_of(node: source.node)

        assert_equal parse_type("::Integer"), typing.cursor_context.context.type_env[:x]
        assert_nil typing.cursor_context.context.type_env[:z]

        assert_equal parse_type("::Integer"), pair.context.type_env[:x]
        assert_equal parse_type("::Integer"), pair.context.type_env[:z]

        assert_empty typing.errors
      end
    end
  end

  def test_lvar_without_annotation_redef
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
x = 1
x = ""
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal parse_type("::String"), typing.type_of(node: source.node)
        assert_empty typing.errors
      end
    end
  end

  def test_lvar_with_annotation_inference
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
# @type var x: _A
x = (_ = nil)
z = x
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal parse_type("::_A"), typing.type_of(node: source.node)
        assert_empty typing.errors
      end
    end
  end

  def test_method_call
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
# @type var x: _C
x = (_ = nil)
x.f
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_no_error typing
        assert_equal parse_type("::_A"), typing.type_of(node: source.node)
      end
    end
  end

  def test_method_call_with_argument
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
# @type var x: _C
# @type var y: _A
x = (_ = nil)
y = (_ = nil)
x.g(y)
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal parse_type("::_B"), typing.type_of(node: source.node)
        assert_empty typing.errors
      end
    end
  end

  def test_method_call_incompatible_argument_type
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
# @type var x: _C
# @type var y: _B
x = (_ = nil)
y = (_ = nil)
x.g(y)
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal parse_type("::_B"), typing.type_of(node: source.node)

        assert_equal 1, typing.errors.size
        assert_argument_type_mismatch typing.errors[0],
                                      expected: parse_type("::_A"),
                                      actual: parse_type("::_B")
      end
    end
  end

  def test_method_call_no_error_if_any
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
x = (_ = nil)
x.no_such_method
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal parse_type("untyped"), typing.type_of(node: source.node)
        assert_empty typing.errors
      end
    end
  end

  def test_method_call_no_method_error
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
# @type var x: _C
x = (_ = nil)
x.no_such_method
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal parse_type("untyped"), typing.type_of(node: source.node)

        assert_equal 1, typing.errors.size
        assert_no_method_error typing.errors.first, method: :no_such_method, type: parse_type("::_C")
      end
    end
  end

  def test_method_call_missing_argument
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
# @type var x: _A
# @type var a: _C
a = (_ = nil)
x = (_ = nil)
a.g()
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal parse_type("::_B"), typing.type_of(node: source.node)

        assert_typing_error(typing, size: 1) do |errors|
          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::InsufficientPositionalArguments, error
            assert_equal "g()", error.location.source
          end
        end
      end
    end
  end

  def test_method_call_extra_args
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
# @type var x: _A
# @type var a: _C
a = (_ = nil)
x = (_ = nil)
a.g(_ = 1, _ = 2, _ = 3)
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal parse_type("::_B"), typing.type_of(node: source.node)

        assert_typing_error(typing, size: 1) do |errors|
          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::UnexpectedPositionalArgument, error
            assert_equal "_ = 3", error.location.source
          end
        end
      end
    end
  end

  def test_keyword_call
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
# @type var x: _C
# @type var a: _A
# @type var b: _B
x = (_ = nil)
a = (_ = nil)
b = (_ = nil)
x.h(a: a, b: b)
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal parse_type("::_C"), typing.type_of(node: source.node)
        assert_empty typing.errors
      end
    end
  end

  def test_keyword_missing
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
# @type var x: _C
x = (_ = nil)
x.h()
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal parse_type("::_C"), typing.type_of(node: source.node)

        assert_typing_error(typing, size: 1) do |errors|
          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::InsufficientKeywordArguments, error
            assert_equal [:a], error.missing_keywords
          end
        end
      end
    end
  end

  def test_extra_keyword_given
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
# @type var x: _C
x = (_ = nil)
x.h(a: (_ = nil), b: (_ = nil), c: (_ = nil))
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal parse_type("::_C"), typing.type_of(node: source.node)

        assert_typing_error(typing, size: 1) do |errors|
          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::UnexpectedKeywordArgument, error
            assert_equal "c: (_ = nil)", error.node.loc.expression.source
            assert_equal "c", error.location.source
          end
        end
      end
    end
  end

  def test_keyword_typecheck
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
# @type var x: _C
# @type var y: _B
x = (_ = nil)
y = (_ = nil)
x.h(a: y)
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal parse_type("::_C"), typing.type_of(node: source.node)

        assert_typing_error(typing, size: 1) do |errors|
          assert_any! errors do |error|
            assert_instance_of Diagnostic::Ruby::ArgumentTypeMismatch, error
            assert_equal parse_type("::_A"), error.expected
            assert_equal parse_type("::_B"), error.actual
          end
        end
      end
    end
  end

  def test_def_no_params
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
def foo
  # @type var x: _A
  x = (_ = nil)

end
      EOF

      with_standard_construction(checker, source, cursor: [4, 0]) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal parse_type("untyped"), typing.type_of(node: dig(source.node, 2))
        assert_equal parse_type("::_A"), typing.cursor_context.context.type_env[:x]
      end
    end
  end

  def test_def_param
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
def foo(x)
  # @type var x: _A
  y = x
end
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        def_body = source.node.children[2]
        assert_equal parse_type("::_A"), typing.type_of(node: def_body)
        assert_equal parse_type("::_A"), typing.type_of(node: def_body.children[1])
      end
    end
  end

  def test_def_param_error
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
def foo(x, y = x)
  # @type var x: _A
  # @type var y: _C
  x
  y
end
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_typing_error(typing, size: 2) do |errors|
          assert_any!(errors) do |error|
            assert_incompatible_assignment(
              error,
              lhs_type: parse_type("::_C"),
              rhs_type: parse_type("::_A")
            ) do |error|
              assert_equal :optarg, error.node.type
              assert_equal :y, error.node.children[0]
            end
          end
        end

        x = dig(source.node, 2, 0)
        y = dig(source.node, 2, 1)

        assert_equal parse_type("::_A"), typing.type_of(node: x)
        assert_equal parse_type("::_C"), typing.type_of(node: y)
      end
    end
  end

  def test_def_kw_param_error
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
def foo(x:, y: x)
  # @type var x: _A
  # @type var y: _C
  x
  y
end
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_typing_error(typing) do |errors|
          assert_any!(errors) do |error|
            assert_incompatible_assignment error,
              lhs_type: parse_type("::_C"),
              rhs_type: parse_type("::_A") do |error|
              assert_equal :kwoptarg, error.node.type
              assert_equal :y, error.node.children[0]
            end
          end
        end

        x = dig(source.node, 2, 0)
        y = dig(source.node, 2, 1)

        assert_equal parse_type("::_A"), typing.type_of(node: x)
        assert_equal parse_type("::_C"), typing.type_of(node: y)
      end
    end
  end

  def test_def_optional_param
    with_checker <<RBS do |checker|
class TestDefOptional
  def foo: (?Array[String], ?b: Hash[Symbol, Integer]) -> void
end
RBS
      source = parse_ruby(<<-RUBY)
class TestDefOptional
  def foo(a = [], b: {})
  end
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)
        assert_no_error typing
      end
    end
  end

  def test_block
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
# @type var a: _X
a = (_ = nil)

b = a.f do |x|
  # @type var x: _A
  # @type var y: _B
  y = (_ = nil)
  x
  y
end

a
b
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        a = dig(source.node, 2)
        b = dig(source.node, 3)
        x = dig(source.node, 1, 1, 2, 1)
        y = dig(source.node, 1, 1, 2, 2)

        assert_equal parse_type("::_X"), typing.type_of(node: a)
        assert_equal parse_type("::_C"), typing.type_of(node: b)
        assert_equal parse_type("::_A"), typing.type_of(node: x)
        assert_equal parse_type("::_B"), typing.type_of(node: y)
      end
    end
  end

  def test_block_shadow
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
# @type var a: _X
a = (_ = nil)

a.f do |a|
  # @type var a: _A
  b = a
end
      EOF

      with_standard_construction(checker, source, cursor: [7, 0]) do |construction, typing|
        pair = construction.synthesize(source.node)

        assert_equal parse_type("::_X"), pair.context.type_env[:a]

        assert_equal parse_type("::_A"), typing.cursor_context.context.type_env[:a]
        assert_equal parse_type("::_A"), typing.cursor_context.context.type_env[:b]
      end
    end
  end

  def test_block_param_type
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
# @type var x: _X
x = (_ = nil)

x.f do |a|
  # @type var d: _D
  a
  d = (_ = nil)
end
      EOF

      with_standard_construction(checker, source, cursor: [8, 0]) do |construction, typing|
        pair = construction.synthesize(source.node)

        assert_no_error typing

        assert_equal parse_type("::_X"), pair.context.type_env[:x]
        assert_nil pair.context.type_env[:a]
        assert_nil pair.context.type_env[:d]

        typing.cursor_context.context.tap do |context|
          assert_equal parse_type("::_A"), context.type_env[:a]
          assert_equal parse_type("::_D"), context.type_env[:d]
          assert_equal parse_type("::_X"), context.type_env[:x]
        end
      end
    end
  end

  def test_block_extra_missing_params
    with_checker(<<-RBS) do |checker|
class M1
  def foo: () { (Integer, String, bool) -> void } -> void
end

class M2
  def foo: () { (String, Integer) -> void } -> void
end
    RBS

      source = parse_ruby(<<-EOF)
x = [M1.new, M2.new][0]

x.foo do |a|
  nil
end

x.foo do |a, b, c|
  nil
end
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_typing_error(typing, size: 2)
      end
    end
  end

  def test_block_value_type
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
# @type var x: _X
x = (_ = nil)

x.f do |a|
  a
end
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        pair = construction.synthesize(source.node)

        assert_typing_error(typing, size: 1) do |errors|
          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::BlockBodyTypeMismatch, error
            assert_equal parse_type("::_D"), error.expected
            assert_equal parse_type("::_A"), error.actual
          end
        end

        assert_equal parse_type("::_X"), pair.context.type_env[:x]
      end
    end
  end

  def test_block_break_type
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
# @type var x: _X
x = (_ = nil)

x.f do |a|
  break a
  # @type var d: _D
  d = (_ = nil)
end
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        # break a
        #       ^
        assert_equal parse_type("::_A"), typing.type_of(node: dig(source.node, 1, 2, 0, 0))

        assert_equal 1, typing.errors.size
        assert_break_type_mismatch typing.errors[0], expected: parse_type("::_C"), actual: parse_type("::_A")
      end
    end
  end

  def test_return_type_annotation
    with_checker(<<~RBS) do |checker|
        class C
          def foo: () -> untyped
        end
      RBS
      source = parse_ruby(<<-EOF)
class C
  def foo()
    # @type return: _A
    # @type var a: _A
    a = (_ = nil)
    return a
  end
end
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
      end
    end
  end

  def test_return_error
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
def foo()
  # @type return: _X
  # @type var a: _A
  a = (_ = nil)
  return a
end
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_any typing.errors do |error|
          error.is_a?(Diagnostic::Ruby::ReturnTypeMismatch) && error.expected == parse_type("::_X") && error.actual == parse_type("::_A")
        end
      end
    end
  end

  def test_return_hint
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
def foo()
  # @type return: Array[Integer]
  return []
end
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_all!(typing.errors) do
          assert_instance_of Diagnostic::Ruby::UndeclaredMethodDefinition, _1
        end
      end
    end
  end

  def test_constant_annotation
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
# @type const Hello: Integer
# @type var hello: Integer
hello = Hello
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
      end
    end
  end

  def test_constant_annotation2
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
# @type const Hello::World: Integer
Hello::World = ""
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_any typing.errors do |error|
          error.is_a?(Diagnostic::Ruby::IncompatibleAssignment)
        end

        assert_equal parse_type("::Integer"), typing.type_of(node: source.node)
      end
    end
  end

  def test_constant_signature
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
# @type var x: String
x = String
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_any typing.errors do |error|
          error.is_a?(Diagnostic::Ruby::IncompatibleAssignment)
        end
      end
    end
  end

  def test_constant_signature2
    with_checker <<-EOS do |checker|
X: Module
    EOS
      source = parse_ruby(<<-EOF)
X = 3
# @type var x: String
x = X
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal 2, typing.errors.size
        assert typing.errors.all? {|error| error.is_a?(Diagnostic::Ruby::IncompatibleAssignment) }
      end
    end
  end

  def test_overloaded_method
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
# @type var k: _Kernel
# @type var a: _A
# @type var c: _C
k = (_ = nil)
a = (_ = nil)
c = (_ = nil)

# @type var b: _B
b = k.foo(a)

# @type var d: _D
d = k.foo(c)
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
      end
    end
  end

  def test_overloaded_method2
    with_checker <<-EOF do |checker|
class Hello
  def foo: (Integer) -> void
         | (String) -> void
end
    EOF
      source = parse_ruby(<<-EOF)
Hello.new.foo([])
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_typing_error(typing, size: 2) do |errors|
          errors[0].tap do |error|
            assert_instance_of Diagnostic::Ruby::UnannotatedEmptyCollection, error
          end

          errors[1].tap do |error|
            assert_instance_of Diagnostic::Ruby::UnresolvedOverloading, error
            assert_equal parse_type("::Hello"), error.receiver_type
            assert_equal :foo, error.method_name
            assert_equal [parse_method_type("(::Integer) -> void"), parse_method_type("(::String) -> void")],
                         error.method_types
          end
        end
      end
    end
  end

  def test_ivar_types
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
def foo
  # @type ivar @x: _A
  # @type var y: _D

  y = (_ = nil)

  @x = y
  y = @x
end
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_typing_error(typing, size: 3) do |errors|
          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::IncompatibleAssignment, error
            assert_equal :ivasgn, error.node.type
            assert_equal :"@x", error.node.children[0]
          end

          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::IncompatibleAssignment, error
            assert_equal :lvasgn, error.node.type
            assert_equal :ivar, error.node.children[1].type
            assert_equal :"@x", error.node.children[1].children[0]
          end
        end
      end
    end
  end

  def test_poly_method_arg
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
# @type var poly: _PolyMethod
poly = (_ = nil)

# @type var string: String
string = poly.snd(1, "a")
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
      end
    end
  end

  def test_poly_method_block
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
# @type var poly: _PolyMethod
poly = (_ = nil)

# @type var string: String
string = poly.try { "string" }
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
      end
    end
  end

  def test_union_type
    with_checker do |checker|
      source = parse_ruby("1")

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal parse_type("_A | _C"),
                     construction.union_type(parse_type("_A"), parse_type("_C"))

        assert_equal parse_type("_A"),
                     construction.union_type(parse_type("_A"), parse_type("_A"))
      end
    end
  end

  def test_module_self
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
module Foo
  # @implements Foo[A]

  block_given?
end
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
      end
    end
  end

  def test_class_constructor_with_signature
    with_checker <<-EOS do |checker|
class Person end
    EOS
      source = parse_ruby("class Person; end")

      with_standard_construction(checker, source) do |construction, typing|
        for_class = construction.for_class(source.node, RBS::TypeName.parse("::Person"), nil)

        assert_equal(
          Annotation::Implements::Module.new(name: RBS::TypeName.parse("::Person"), args: []),
          for_class.module_context.implement_name
        )
        assert_equal parse_type("::Person"), for_class.module_context.instance_type
        assert_equal parse_type("singleton(::Person)"), for_class.module_context.module_type
      end
    end
  end

  def test_class_constructor_without_signature
    with_checker <<-EOF do |checker|
class Address
end
    EOF
      source = parse_ruby("class Person; end")

      with_standard_construction(checker, source) do |construction, typing|
        for_class = construction.for_class(source.node, RBS::TypeName.parse("::Person"), nil)

        assert_nil for_class.module_context.implement_name
        assert_equal parse_type("::Object"), for_class.module_context.instance_type
        assert_equal parse_type("singleton(::Object)"), for_class.module_context.module_type
      end
    end
  end

  def test_class_constructor_nested
    with_checker <<-EOF do |checker|
class Steep::Names::Module end
module Steep
  class Names
  end
end
    EOF
      source = parse_ruby("module Steep; class Names::Module; end; end")

      context = [nil, RBS::TypeName.parse("::Steep")]
      annotations = source.annotations(block: source.node, factory: checker.factory, context: context)
      const_env = ConstantEnv.new(
        factory: factory,
        context: [nil, RBS::TypeName.parse("::Steep")],
        resolver: RBS::Resolver::ConstantResolver.new(builder: factory.definition_builder)
      )
      type_env = TypeEnv.new(const_env)

      module_context = Context::ModuleContext.new(
        instance_type: parse_type("::Steep"),
        module_type: parse_type("singleton(::Steep)"),
        implement_name: nil,
        nesting: const_env.context,
        class_name: nil
      )

      context = Context.new(
        block_context: nil,
        method_context: nil,
        module_context: module_context,
        break_context: nil,
        self_type: parse_type("::Steep"),
        type_env: type_env,
        call_context: MethodCall::TopLevelContext.new,
        variable_context: Context::TypeVariableContext.empty
      )
      typing = Typing.new(source: source, root_context: context, cursor: nil)

      module_name_class_node = source.node.children[1]

      construction = TypeConstruction.new(checker: checker,
                                          source: source,
                                          annotations: annotations,
                                          context: context,
                                          typing: typing)

      for_module = construction.for_class(module_name_class_node, RBS::TypeName.parse("::Steep::Names::Module"), nil)

      assert_equal(
        Annotation::Implements::Module.new(
          name: RBS::TypeName.parse("::Steep::Names::Module"),
          args: []
        ),
        for_module.module_context.implement_name)
    end
  end

  def test_module_constructor_with_signature
    with_checker <<-EOF do |checker|
module Steep end
    EOF

      source = parse_ruby("module Steep; end")

      with_standard_construction(checker, source) do |construction, typing|
        for_module = construction.for_module(source.node, RBS::TypeName.parse("::Steep"))

        assert_equal(
          Annotation::Implements::Module.new(name: RBS::TypeName.parse("::Steep"), args: []),
          for_module.module_context.implement_name
        )
        assert_equal parse_type("::Object & ::Steep"), for_module.module_context.instance_type
        assert_equal parse_type("singleton(::Steep)"), for_module.module_context.module_type
      end
    end
  end

  def test_module_constructor_without_signature
    with_checker <<-EOF do |checker|
module Rails end
    EOF

      source = parse_ruby("module Steep; end")

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        for_module = construction.for_module(source.node, RBS::TypeName.parse("::Steep"))

        assert_nil for_module.module_context.implement_name
        assert_equal parse_type("::BasicObject"), for_module.module_context.instance_type
        assert_equal parse_type("::Module"), for_module.module_context.module_type
      end
    end
  end

  def test_module_constructor_nested
    with_checker <<-EOS do |checker|
module Steep::Printable end

class Steep end
    EOS
      source = parse_ruby("class Steep; module Printable; end; end")

      context = [nil, RBS::TypeName.parse("::Steep")]
      annotations = source.annotations(block: source.node, factory: checker.factory, context: context)
      const_env = ConstantEnv.new(factory: factory, context: [nil, RBS::TypeName.parse("::Steep")], resolver: RBS::Resolver::ConstantResolver.new(builder: factory.definition_builder))
      type_env = TypeEnv.new(const_env)

      module_context = Context::ModuleContext.new(
        instance_type: parse_type("::Steep"),
        module_type: parse_type("singleton(::Steep)"),
        implement_name: nil,
        nesting: const_env.context,
        class_name: RBS::TypeName.parse("::Steep")
      )

      context = Context.new(
        block_context: nil,
        method_context: nil,
        module_context: module_context,
        break_context: nil,
        self_type: parse_type("::Steep"),
        type_env: type_env,
        call_context: MethodCall::ModuleContext.new(type_name: RBS::TypeName.parse("::Steep")),
        variable_context: Context::TypeVariableContext.empty
      )
      typing = Typing.new(source: source, root_context: context, cursor: nil)

      module_node = source.node.children.last

      construction = TypeConstruction.new(checker: checker,
                                          source: source,
                                          annotations: annotations,
                                          context: context,
                                          typing: typing)

      for_module = construction.for_module(module_node, RBS::TypeName.parse("::Steep::Printable"))

      assert_equal(
        Annotation::Implements::Module.new(name: RBS::TypeName.parse("::Steep::Printable"), args: []),
        for_module.module_context.implement_name)
    end
  end

  def test_new_method_constructor
    with_checker <<-EOF do |checker|
class A
  def foo: (String) -> Integer
end
    EOF

      source = parse_ruby("class A; def foo(x); end; end")

      with_standard_construction(checker, source) do |construction, typing|
        type_name = parse_type("::A").name
        instance_definition = checker.factory.definition_builder.build_instance(type_name)

        def_node = source.node.children[2]
        for_method = construction.for_new_method(:foo,
                                                 def_node,
                                                 args: def_node.children[1].children,
                                                 self_type: parse_type("::A"),
                                                 definition: instance_definition)

        method_context = for_method.method_context
        assert_equal :foo, method_context.name
        assert_equal instance_definition.methods[:foo], method_context.method
        assert_equal parse_method_type("(::String) -> ::Integer"), method_context.method_type
        assert_equal parse_type("::Integer"), method_context.return_type

        assert_equal parse_type("::A"), for_method.self_type
        assert_nil for_method.block_context
        assert_equal Set[:x], for_method.context.type_env.local_variable_types.keys.to_set
        assert_equal parse_type("::String"), for_method.context.type_env[:x]
      end
    end
  end

  def test_new_method_constructor_overloaded
    with_checker <<-EOS do |checker|
class A
  def foo: (String) -> Integer
         | (Object) -> Integer
end
EOS

      source = parse_ruby("class A; def foo(x); end; end")

      with_standard_construction(checker, source) do |construction, typing|
        type_name = parse_type("::A").name
        instance_definition = checker.factory.definition_builder.build_instance(type_name)

        def_node = source.node.children[2]
        for_method = construction.for_new_method(:foo,
                                                 def_node,
                                                 args: def_node.children[1].children,
                                                 self_type: parse_type("::A"),
                                                 definition: instance_definition)

        method_context = for_method.method_context
        assert_equal :foo, method_context.name
        assert_equal parse_method_type("(::Object | ::String) -> ::Integer"), method_context.method_type
        assert_equal parse_type("::Integer"), method_context.return_type

        assert_equal parse_type("::A"), for_method.self_type
        assert_nil for_method.block_context
        assert_equal parse_type("::Object | ::String"), for_method.context.type_env[:x]

        assert_empty typing.errors
      end
    end
  end

  def test_new_method_constructor_method_annotation
    with_checker <<-EOS do |checker|
class A
  def foo: () -> Integer
         | [A] () { () -> A } -> A
end
    EOS
      source = parse_ruby(<<-EOF)
class A
  # @type method foo: () ?{ () -> untyped } -> untyped
  def foo()
  end
end
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        type_name = parse_type("::A").name
        instance_definition = checker.factory.definition_builder.build_instance(type_name)

        def_node = source.node.children[2]

        for_method = construction.for_new_method(:foo,
                                                 def_node,
                                                 args: def_node.children[1].children,
                                                 self_type: parse_type("::A"),
                                                 definition: instance_definition)

        method_context = for_method.method_context
        assert_equal :foo, method_context.name
        assert_equal parse_method_type("() ?{ () -> untyped } -> untyped"), method_context.method_type
        assert_equal parse_type("untyped"), method_context.return_type

        assert_equal parse_type("::A"), for_method.self_type
        assert_nil for_method.block_context
        assert_empty for_method.context.type_env.local_variable_types.keys

        assert_empty typing.errors
      end
    end
  end

  def test_new_method_constructor_with_return_type
    with_checker <<-EOF do |checker|
class A
  def foo: (String) -> Integer
end
    EOF

      source = parse_ruby(<<-RUBY)
class A
  def foo(x)
    # @type return: String
  end
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type_name = parse_type("::A").name
        instance_definition = checker.factory.definition_builder.build_instance(type_name)
        def_node = source.node.children[2]

        for_method = construction.for_new_method(:foo,
                                                 def_node,
                                                 args: def_node.children[1].children,
                                                 self_type: parse_type("::A"),
                                                 definition: instance_definition)

        method_context = for_method.method_context
        assert_equal :foo, method_context.name
        assert_equal parse_method_type("(::String) -> ::Integer"), method_context.method_type
        assert_equal parse_type("::String"), method_context.return_type

        assert_equal parse_type("::A"), for_method.self_type
        assert_nil for_method.block_context
        assert_equal Set[:x], for_method.context.type_env.local_variable_types.keys.to_set
        assert_equal parse_type("::String"), for_method.context.type_env[:x]

        assert_equal 1, typing.errors.size
        assert_instance_of Diagnostic::Ruby::MethodReturnTypeAnnotationMismatch, typing.errors.first
      end
    end
  end

  def test_relative_type_name
    with_checker <<-EOF do |checker|
class A::String
  def aaaaa: -> untyped
end

module A
end
    EOF

      source = parse_ruby(<<-RUBY)
class A
  def foo
    # @type var x: String
    x = ""
  end

  # @type method bar: -> String
  def bar
    ""
  end
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_typing_error(typing, size: 4) do |errors|
          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::IncompatibleAssignment, error
            assert_equal parse_type("::String"), error.rhs_type
            assert_equal parse_type("::A::String"), error.lhs_type
          end

          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::MethodBodyTypeMismatch, error
            assert_equal parse_type("::String"), error.actual
            assert_equal parse_type("::A::String"), error.expected
          end

          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::ClassModuleMismatch, error
            assert_equal "::A", error.name.to_s
          end
        end
      end
    end
  end

  def test_namespace_module
    with_checker <<-EOS do |checker|
class A
  def foobar: -> untyped
end

class B
  def hello: () -> void
end

class B
  class C
  end
end

class C
  def hello: () -> void
end

class C
  def hello: () -> void
end
    EOS

      source = parse_ruby(<<-RUBY)
class A
end

class B
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal 2, typing.errors.size

        typing.errors[0].tap do |error|
          assert_instance_of Diagnostic::Ruby::MethodDefinitionMissing, error
          assert_equal "::A", error.module_name.to_s
        end

        typing.errors[1].tap do |error|
          assert_instance_of Diagnostic::Ruby::MethodDefinitionMissing, error
          assert_equal "::B", error.module_name.to_s
        end
      end
    end
  end

  def test_namespace_module_nested
    with_checker <<-EOF do |checker|
class A
end

class A::String
  def foo: -> untyped
end
    EOF

      source = parse_ruby(<<-RUBY)
class A::String < Object
  def foo
    # @type var x: String
    x = ""

    # @type var y: ::String
    y = ""
  end
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_masgn_1
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
# @type var a: String
# @type ivar @b: String
a, @b = 1, 2.0
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_typing_error(typing, size: 2) do |errors|
          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::IncompatibleAssignment, error
            assert_equal :lvasgn, error.node.type
          end

          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::IncompatibleAssignment, error
            assert_equal :ivasgn, error.node.type
          end
        end
      end
    end
  end

  def test_masgn_tuple
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
# @type var tuple: [Integer, Integer, Symbol]
tuple = [1, 2, :foo]

# @type var a: String
# @type ivar @b: String
a, @b, c = tuple
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        pair = construction.synthesize(source.node)

        assert_equal 2, typing.errors.size
        assert_any typing.errors do |error|
          error.is_a?(Diagnostic::Ruby::IncompatibleAssignment) &&
            error.node.type == :lvasgn
        end
        assert_any typing.errors do |error|
          error.is_a?(Diagnostic::Ruby::IncompatibleAssignment) &&
            error.node.type == :ivasgn
        end

        assert_equal parse_type("::String"), pair.context.type_env[:a]
        assert_equal parse_type("::Symbol"), pair.context.type_env[:c]
      end
    end
  end

  def test_masgn_nested_tuple
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
a, (b, c) = 1, [true, "hello"]
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        pair = construction.synthesize(source.node)

        assert_no_error typing

        assert_equal parse_type("::Integer"), pair.context.type_env[:a]
        assert_equal parse_type("bool"), pair.context.type_env[:b]
        assert_equal parse_type("::String"), pair.context.type_env[:c]
      end
    end
  end

  def test_masgn_tuple_array
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
a, *b, c = [1, 2, "x", :foo]
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        _, _, context = construction.synthesize(source.node)

        assert_no_error typing

        assert_equal parse_type("::Integer"), context.type_env[:a]
        assert_equal parse_type("[::Integer, ::String]"), context.type_env[:b]
        assert_equal parse_type("::Symbol"), context.type_env[:c]
      end
    end
  end

  def test_masgn_array
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
# @type var a: String
# @type ivar @b: String
x = [1, 2]
a, @b, c = x
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        pair = construction.synthesize(source.node)

        assert_equal parse_type("::Integer?"), pair.context.type_env[:c]

        assert_typing_error(typing, size: 2) do |errors|
          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::IncompatibleAssignment, error
            assert_equal :lvasgn, error.node.type
            assert_equal parse_type("::Integer?"), error.rhs_type
          end

          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::IncompatibleAssignment, error
            assert_equal :ivasgn, error.node.type
            assert_equal parse_type("::Integer?"), error.rhs_type
          end
        end
      end
    end
  end

  def test_masgn_splat
    with_checker do |checker|
      source = parse_ruby(<<-RUBY)
# @type var x: Array[Integer]
x = []
a, *b, c = x
      RUBY


      with_standard_construction(checker, source) do |construction, typing|
        type, _, context = construction.synthesize(source.node)

        assert_no_error typing

        assert_equal parse_type("::Array[::Integer]"), type
        assert_equal parse_type("::Integer?"), context.type_env[:a]
        assert_equal parse_type("::Array[::Integer]"), context.type_env[:b]
        assert_equal parse_type("::Integer?"), context.type_env[:c]
      end
    end
  end

  def test_masgn_splat_unnamed
    with_checker do |checker|
      source = parse_ruby(<<-RUBY)
# @type var x: Array[Integer]
x = []
a, *, c = x
      RUBY


      with_standard_construction(checker, source) do |construction, typing|
        type, _, context = construction.synthesize(source.node)

        assert_no_error typing

        assert_equal parse_type("::Array[::Integer]"), type
        assert_equal parse_type("::Integer?"), context.type_env[:a]
        assert_nil context.type_env[:b]
        assert_equal parse_type("::Integer?"), context.type_env[:c]
      end
    end
  end

  def test_masgn_optional
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
# @type var tuple: [Integer, String]?
tuple = _ = nil
a, b = x = tuple
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        _, _, context = construction.synthesize(source.node)

        assert_no_error typing

        assert_equal parse_type("::Integer?"), context.type_env[:a]
        assert_equal parse_type("::String?"), context.type_env[:b]
        assert_equal parse_type("[::Integer, ::String]?"), context.type_env[:x]
      end
    end
  end

  def test_masgn_to_ary
    with_checker(<<-RBS) do |checker|
class WithToAry
  def to_ary: () -> [Integer, String, bool]
end
      RBS
      source = parse_ruby(<<-EOF)
x = (a, b = WithToAry.new())
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        _, _, context = construction.synthesize(source.node)

        assert_no_error typing

        assert_equal parse_type("::Integer"), context.type_env[:a]
        assert_equal parse_type("::String"), context.type_env[:b]
        assert_equal parse_type("::WithToAry"), context.type_env[:x]
      end
    end
  end

  def test_masgn_to_ary_error
    with_checker(<<-RBS) do |checker|
class WithToAry
  def to_ary: () -> Integer
end
      RBS
      source = parse_ruby(<<-EOF)
x = (a, b = WithToAry.new())
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        _, _, context = construction.synthesize(source.node)

        assert_typing_error(typing, size: 1) do |errors|
          errors[0].tap do |error|
            assert_instance_of Diagnostic::Ruby::MultipleAssignmentConversionError, error
            assert_equal parse_type("::WithToAry"), error.original_type
            assert_equal parse_type("::Integer"), error.returned_type
            assert_equal "WithToAry.new()", error.location.source
          end
        end

        assert_equal parse_type("untyped"), context.type_env[:a]
        assert_equal parse_type("untyped"), context.type_env[:b]
        assert_equal parse_type("::WithToAry"), context.type_env[:x]
      end
    end
  end

  def test_masgn_no_conversion
    with_checker(<<-RBS) do |checker|
      RBS
      source = parse_ruby(<<-EOF)
x = (a, b = 123)
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        _, _, context = construction.synthesize(source.node)

        assert_no_error typing

        assert_equal parse_type("::Integer"), context.type_env[:a]
        assert_equal parse_type("nil"), context.type_env[:b]
        assert_equal parse_type("::Integer"), context.type_env[:x]
      end
    end
  end

  def test_masgn_optional_conditional
    with_checker do |checker|
      source = parse_ruby(<<-RUBY)
# @type var tuple: [Integer, String]?
tuple = _ = nil
if x = (a, b = tuple)
  a + 1
  b + "a"
else
  return
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        _, _, context = construction.synthesize(source.node)

        assert_no_error typing

        assert_equal parse_type("::Integer"), context.type_env[:a]
        assert_equal parse_type("::String"), context.type_env[:b]
        assert_equal parse_type("[::Integer, ::String]"), context.type_env[:x]
      end
    end
  end

  def test_masgn_untyped
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
a, @b = _ = nil
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        type, constr, context = construction.synthesize(source.node)

        assert_all!(typing.errors) do |error|
          assert_instance_of Diagnostic::Ruby::UnknownInstanceVariable, error
        end

        assert_equal parse_type("untyped"), context.type_env[:a]
      end
    end
  end

  def test_union_send_error
    with_checker do |checker|
      source = parse_ruby(<<-RUBY)
# @type var x: Integer | String
x = (_ = nil)
y = x + ""
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal 1, typing.errors.size
        assert_any typing.errors do |error|
          error.is_a?(Diagnostic::Ruby::UnresolvedOverloading)
        end
      end
    end
  end

  def test_intersection_send
    with_checker do |checker|
      source = parse_ruby(<<-RUBY)
# @type var x: Integer & String
x = (_ = nil)
y = x.to_str
z = x.to_int
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        pair = construction.synthesize(source.node)

        assert_no_error typing
        assert_equal parse_type("::String"), pair.context.type_env[:y]
        assert_equal parse_type("::Integer"), pair.context.type_env[:z]
      end
    end
  end

  def test_union_send
    with_checker do |checker|
      source = parse_ruby(<<-RUBY)
# @type var x: Integer | String
x = (_ = nil)
y = x.itself
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        pair = construction.synthesize(source.node)

        assert_no_error typing
        assert_equal parse_type("::String | ::Integer"), pair.constr.context.type_env[:y]
      end
    end
  end

  def test_masgn_array_error
    with_checker do |checker|
      source = parse_ruby(<<-RUBY)
a, @b = 3
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_typing_error(typing, size: 1)

        assert_equal 1, typing.errors.size
        assert_any typing.errors do |error|
          error.is_a?(Diagnostic::Ruby::UnknownInstanceVariable)
        end
      end
    end
  end

  def test_op_asgn
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
# @type var a: String
a = ""
a += ""
a += 3

b = _ = nil
b += 3
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        _, _, context = construction.synthesize(source.node)

        assert_equal 1, typing.errors.size
        typing.errors[0].tap do |error|
          assert_instance_of Diagnostic::Ruby::ArgumentTypeMismatch, error
          assert_equal dig(source.node, 2, 2), error.node
        end

        assert_equal parse_type("untyped"), context.type_env[:b]
      end
    end
  end

  def test_op_asgn_send
    with_checker <<-RBS do |checker|
class WithAttribute
  attr_accessor foo: String
end
    RBS
      source = parse_ruby(<<-EOF)
a = WithAttribute.new
a.foo += "!!"
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_while0
    with_checker do |checker|
      source = parse_ruby(<<-RUBY)
while true
  break
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
      end
    end
  end

  def test_while2
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
tap do
  while true
    break 30
  end
end
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_while3
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
while true
  tap do
    break self
  end
end
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
      end
    end
  end

  def test_while_post
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
begin
  a = 3
end while true
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
      end
    end
  end

  def test_while_gets
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
while line = gets
  line + ""
end
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_until_gets
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
until line = gets
  line + ""
end
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal 1, typing.errors.size
        typing.errors[0].tap do |error|
          assert_instance_of Diagnostic::Ruby::NoMethod, error
          assert_equal parse_type("nil"), error.type
          assert_equal :+, error.method
        end
      end
    end
  end

  def test_post_loop
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
line = gets

begin
  line + ""
end while line = gets
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal 1, typing.errors.size
        typing.errors[0].tap do |error|
          assert_instance_of Diagnostic::Ruby::NoMethod, error
          assert_equal parse_type("::String?"), error.type
          assert_equal :+, error.method
        end
      end
    end
  end

  def test_for_0
    with_checker <<-'RBS' do |checker|
    RBS
      source = parse_ruby(<<-'RUBY')
for x in [1,2,3]
  y = x + 1
end

puts y.to_s
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        _, _, context = construction.synthesize(source.node)

        assert_no_error typing

        assert_equal parse_type("::Integer?"), context.type_env[:x]
        assert_equal parse_type("::Integer?"), context.type_env[:y]
      end
    end
  end

  def test_for_1
    with_checker <<-'RBS' do |checker|
    RBS
      source = parse_ruby(<<-'RUBY')
for x in [1]
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        _, _, context = construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_for_2
    with_checker <<-'RBS' do |checker|
    RBS
      source = parse_ruby(<<-'RUBY')
for x in self
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        _, _, context = construction.synthesize(source.node)

        assert_equal 1, typing.errors.size

        assert_any!(typing.errors) do |error|
          assert_instance_of Diagnostic::Ruby::NoMethod, error
        end
      end
    end
  end

  def test_range
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
# @type var a: Range[Integer]
a = 1..2
a = 2..."a"
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal 1, typing.errors.size
        assert_any typing.errors do |error|
          error.is_a?(Diagnostic::Ruby::IncompatibleAssignment)
        end
      end
    end
  end

  def test_regexp
    with_checker do |checker|
      source = parse_ruby(<<-'EOF')
# @type var a: Regexp
a = /./
a = /#{a + 3}/
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal 1, typing.errors.size
        assert_any typing.errors do |error|
          error.is_a?(Diagnostic::Ruby::NoMethod)
        end
      end
    end
  end

  def test_nth_ref
    with_checker do |checker|
      source = parse_ruby(<<-'EOF')
# @type var a: Integer
a = $1
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal 1, typing.errors.size
        assert_any typing.errors do |error|
          error.is_a?(Diagnostic::Ruby::IncompatibleAssignment)
        end
      end
    end
  end

  def test_or_and_asgn
    with_checker do |checker|
      source = parse_ruby(<<-'EOF')
a = 3
a &&= a
a ||= a + "foo"
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal 1, typing.errors.size
        assert_any typing.errors do |error|
          error.is_a?(Diagnostic::Ruby::UnresolvedOverloading)
        end
      end
    end
  end

  def test_or_and_asgn_method
    with_checker(<<-RBS) do |checker|
class OrAndAsgn
  def or_asgn: () -> Integer
  def and_asgn: () -> Integer
  def var=: (Integer) -> Integer
end
RBS
      source = parse_ruby(<<-'EOF')
class OrAndAsgn
  def or_asgn
    self.var ||= 1
  end

  def and_asgn
    self.var &&= 2
  end

  def var=(a)
    a
  end
end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)
        assert_equal 2, typing.errors.size
        assert_all typing.errors do |error|
          assert_equal :var, error.method
          error.is_a?(Diagnostic::Ruby::NoMethod)
        end
      end
    end
  end

  def test_next
    with_checker do |checker|
      source = parse_ruby(<<-'EOF')
while true
  next
end
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
      end
    end
  end

  def test_next1
    with_checker do |checker|
      source = parse_ruby(<<-'EOF')
while true
  next 3
end
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        refute_empty typing.errors
        assert_any typing.errors do |error|
          error.is_a?(Diagnostic::Ruby::UnexpectedJumpValue)
        end
      end
    end
  end

  def test_next2
    with_checker do |checker|
      source = parse_ruby(<<-'EOF')
tap do |a|
  next
end
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
      end
    end
  end

  def test_method_arg_assign
    with_checker do |checker|
      source = parse_ruby(<<-'RUBY')
# @type method f: (Integer?) -> void
def f(x)
  if x
    x = "forever"
    x + ""
  end
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)
        assert_no_error typing
      end
    end
  end

  def test_restargs
    with_checker do |checker|
      source = parse_ruby(<<-'EOF')
def f(*x)
  # @type var y: String
  y = x
end
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_any!(typing.errors, size: 2) do |error|
          assert_instance_of Diagnostic::Ruby::IncompatibleAssignment, error
          assert_equal parse_type("::String"), error.lhs_type
          assert_equal parse_type("::Array[untyped]"), error.rhs_type
        end
      end
    end
  end

  def test_restargs2
    with_checker do |checker|
      source = parse_ruby(<<-'EOF')
# @type method f: (*String) -> untyped
def f(*x)
  # @type var y: String
  y = x
end
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal 1, typing.errors.size
        assert_any typing.errors do |error| error.is_a?(Diagnostic::Ruby::IncompatibleAssignment) end
      end
    end
  end

  def test_gvar
    with_checker "$HOGE: Integer" do |checker|
      source = parse_ruby(<<-'EOF')
$HOGE = 3
x = $HOGE
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
      end
    end
  end

  def test_gvar1
    with_checker "$HOGE: Integer" do |checker|
      source = parse_ruby(<<-'EOF')
$HOGE = ""

# @type var x: Array[String]
x = $HOGE
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal 2, typing.errors.size
        assert typing.errors.all? {|error| error.is_a?(Diagnostic::Ruby::IncompatibleAssignment) }
      end
    end
  end

  def test_gvar2
    with_checker do |checker|
      source = parse_ruby(<<-'EOF')
$HOGE = 3
x = $HOGE
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_typing_error(typing, size: 2) do |errors|
          assert_all!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::UnknownGlobalVariable, error
          end
        end
      end
    end
  end

  def test_gvar3
    with_checker(<<RBS) do |checker|
$TEST: bool
RBS
      source = parse_ruby(<<RUBY)
def foo
  $TEST
end
RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _ = construction.synthesize(source.node)

        assert_all!(typing.errors) do |error|
          assert_instance_of Diagnostic::Ruby::UndeclaredMethodDefinition, error
        end
      end
    end
  end

  def test_ivar
    with_checker <<-EOF do |checker|
class A
  def foo: -> String
  @foo: String
end
    EOF
      source = parse_ruby(<<-'EOF')
class A
  def foo
    @foo
  end
end
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
      end
    end
  end

  def test_ivar2
    with_checker <<-EOF do |checker|
class A
  @foo: String
end
    EOF
      source = parse_ruby(<<-'EOF')
class A
  x = @foo
end
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal 1, typing.errors.size
        assert_any typing.errors do |error| error.is_a?(Diagnostic::Ruby::FallbackAny) end
      end
    end
  end

  def test_splat
    with_checker do |checker|
      source = parse_ruby(<<-'EOF')
a = [1]

# @type var b: Array[String]
b = [*a]
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal 1, typing.errors.size
        assert_any typing.errors do |error|
          error.is_a?(Diagnostic::Ruby::IncompatibleAssignment)
        end
      end
    end
  end

  def test_splat_range
    with_checker do |checker|
      source = parse_ruby(<<-'EOF')
# @type var b: Array[String]
b = [*1...3]
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal 1, typing.errors.size
        assert_any typing.errors do |error|
          error.is_a?(Diagnostic::Ruby::IncompatibleAssignment)
        end
      end
    end
  end

  def test_splat_object
    with_checker do |checker|
      source = parse_ruby(<<-'EOF')
# @type var a: Array[Symbol] | Integer
a = (_ = nil)
b = [*a, *["foo"]]
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        pair = construction.synthesize(source.node)

        assert_no_error typing
        assert_equal parse_type("::Array[::Integer|::Symbol|::String]"), pair.context.type_env[:b]
      end
    end
  end

  def test_splat_arg
    with_checker <<-EOF do |checker|
class A
  def initialize: () -> untyped
  def gen: (*Integer) -> String
end
    EOF
      source = parse_ruby(<<-'EOF')
a = A.new
a.gen(*["1"])
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        pair = construction.synthesize(source.node)

        assert_equal 1, typing.errors.size
        assert_any typing.errors do |error|
          error.is_a?(Diagnostic::Ruby::ArgumentTypeMismatch)
        end

        assert_equal parse_type("::A"), pair.context.type_env[:a]
      end
    end
  end

  def test_splat_arg2
    with_checker <<-EOF do |checker|
class A
  def initialize: () -> untyped
  def gen: (*Integer) -> String
end
      EOF
      source = parse_ruby(<<-'EOF')
a = A.new
b = [1]
a.gen(*b)
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_self
    with_checker <<-EOF do |checker|
class Hoge
  def foo: () -> self
end
    EOF

      source = parse_ruby(<<-'EOF')
class Hoge
  def foo
    self
  end
end
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
      end
    end
  end

  def test_self_send
    with_checker <<-EOF do |checker|
class Hoge
  def foo: () -> self
end
    EOF

      source = parse_ruby(<<-'EOF')
class Hoge
  def foo
    self.foo.foo
  end
end
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_self_subtype
    with_checker <<-EOF do |checker|
class Hoge
  def foo: () -> void
end
    EOF

      source = parse_ruby(<<-'EOF')
class Hoge
  def foo
    # @type var x: Hoge
    x = self
  end
end
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
      end
    end
  end

  def test_self_subtype_poly
    with_checker <<-EOF do |checker|
class Hoge
  def foo: () -> self
end

class Huga < Hoge
  def bar: -> void
end

    EOF

      source = parse_ruby(<<-'EOF')
class Huga < Hoge
  def bar
    foo.bar
  end
end
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
      end
    end
  end

  def test_self_subtype_error
    with_checker <<-EOF do |checker|
class Hoge
  def foo: () -> self
end

class Huga < Hoge
  def bar: -> void
end

    EOF

      source = parse_ruby(<<-'EOF')
class Hoge
  def foo
    Hoge.new
  end
end
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        refute_empty typing.errors
      end
    end
  end

  def test_instance_type_defn
    with_checker <<-EOF do |checker|
class Hoge
  def foo: (instance) -> void
  def bar: () -> instance
end
    EOF

      source = parse_ruby(<<-'EOF')
class Hoge
  def foo(hoge)
    hoge.bar()

    # @type var x: Hoge
    x = hoge
  end

  def bar
    Hoge.new()
  end
end
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_instance_type_send
    with_checker <<-EOF do |checker|
class Hoge
  def foo: (instance) -> void
  def bar: () -> instance
end
    EOF

      source = parse_ruby(<<-'EOF')
Hoge.new.foo(Hoge.new)
Hoge.new.bar().bar()
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_instance_type_poly
    with_checker <<-EOF do |checker|
class Hoge
  def foo: (instance) -> void
end

class Huga < Hoge
end
    EOF

      source = parse_ruby(<<-'EOF')
Hoge.new.foo(Huga.new)
Huga.new.foo(Hoge.new)
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_typing_error(typing, size: 1) do |errors|
          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::ArgumentTypeMismatch, error
          end
        end
      end
    end
  end

  def test_class_type_defn
    with_checker <<-EOF do |checker|
class Hoge
  def foo: (class) -> void
  def bar: () -> class
end
    EOF

      source = parse_ruby(<<-'EOF')
class Hoge
  def foo(hoge)
    hoge.new
  end

  def bar
    Hoge
  end
end
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_class_type_send
    with_checker <<-EOF do |checker|
class Hoge
  def foo: (class) -> void
  def bar: () -> class
end
    EOF

      source = parse_ruby(<<-'EOF')
Hoge.new.foo(Hoge)
Hoge.new.bar().new
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_class_type_poly
    with_checker <<-EOF do |checker|
class Hoge
  def foo: (class) -> void
end

class Huga < Hoge
end
    EOF

      source = parse_ruby(<<-'EOF')
Hoge.new.foo(Huga)
Huga.new.foo(Hoge)
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_typing_error(typing, size: 1) do |errors|
          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::ArgumentTypeMismatch, error
          end
        end
      end
    end
  end

  def test_void
    with_checker <<-EOF do |checker|
class Hoge
  def foo: (self) -> void
end
    EOF
      source = parse_ruby(<<-'EOF')
class Hoge
  def foo(a)
    # @type var x: Integer
    x = a.foo(self)
    a.foo(self).class
  end
end
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_typing_error(typing, size: 2)

        assert_any typing.errors do |error|
          error.is_a?(Diagnostic::Ruby::IncompatibleAssignment) && error.rhs_type.is_a?(Steep::AST::Types::Void)
        end
        assert_any typing.errors do |error|
          error.is_a?(Diagnostic::Ruby::NoMethod) && error.type.is_a?(Steep::AST::Types::Void)
        end
      end
    end
  end

  def test_void2
    with_checker <<-EOF do |checker|
class Hoge
  def foo: () { () -> void } -> untyped
end
    EOF
      source = parse_ruby(<<-'EOF')
class Hoge
  def foo()
    # @type var x: String
    x = yield
    x = yield.class

    self.foo { 30 }
  end
end
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_typing_error(typing, size: 2)

        assert_any typing.errors do |error|
          error.is_a?(Diagnostic::Ruby::IncompatibleAssignment) && error.rhs_type.is_a?(Steep::AST::Types::Void)
        end
        assert_any typing.errors do |error|
          error.is_a?(Diagnostic::Ruby::NoMethod) && error.type.is_a?(Steep::AST::Types::Void)
        end
      end
    end
  end

  def test_zip
    with_checker do |checker|
      source = parse_ruby(<<EOF)
a = [1]

# @type var b: ::Array[Integer|String]
b = a.zip(["foo"])
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
      end
    end
  end

  def test_each_with_object
    with_checker do |checker|
      source = parse_ruby(<<EOF)
a = [1]

# @type var b: ::Array[Integer]
b = a.each_with_object([]) do |x, y|
  # @type var y: ::Array[String]
  y << ""
end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_typing_error(typing, size: 2) do |errors|
          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::IncompatibleAssignment, error
          end

          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::IncompatibleAnnotation, error
          end
        end
      end
    end
  end

  def test_each_with_object2
    with_checker do |checker|
      source = parse_ruby(<<EOF)
a = [1]

b = a.each_with_object("") do |x, y|
  y + ""
end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        _, constr = construction.synthesize(source.node)

        assert_no_error typing
        assert_equal parse_type("::String"), constr.context.type_env[:b]
      end
    end
  end

  def test_if_typing
    with_checker do |checker|
      source = parse_ruby(<<EOF)
if _ = 3
  x = 1
  y = (x + 1).to_int
  z = :foo
else
  x = "foo"
  y = (x.to_str).size
end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        pair = construction.synthesize(source.node)

        assert_empty typing.errors

        assert_equal parse_type("::String | ::Integer"), pair.constr.context.type_env[:x]
        assert_equal parse_type("::Integer"), pair.constr.context.type_env[:y]
        assert_equal parse_type("::Symbol?"), pair.constr.context.type_env[:z]
      end
    end
  end

  def test_if_return
    with_checker do |checker|
      source = parse_ruby(<<-RUBY)
if _ = 3
  return
else
  x = :foo
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        pair = construction.synthesize(source.node)

        assert_empty typing.errors

        assert_equal parse_type("::Symbol"), pair.constr.context.type_env[:x]
      end
    end
  end

  def test_if_annotation_success
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type var x: String | Integer
x = (_ = nil)

if _ = 3
  # @type var x: String
  x + ""
else
  # @type var x: Integer
  x + 1
end
EOF

      with_standard_construction(checker, source, cursor: [6, 3]) do |construction, typing|
        construction.synthesize(source.node)
        assert_no_error typing
        assert_equal parse_type("::String"), typing.cursor_context.context.type_env[:x]
      end

      with_standard_construction(checker, source, cursor: [9, 3]) do |construction, typing|
        construction.synthesize(source.node)
        assert_no_error typing
        assert_equal parse_type("::Integer"), typing.cursor_context.context.type_env[:x]
      end
    end
  end

  def test_if_annotation_error
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type var x: Array[String]
x = (_ = nil)

if 3
  # @type var x: String
  x + ""
else
  # @type var x: Integer
  x + 1
end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        typing.errors.find {|error| error.node == dig(source.node, 1, 1) }.tap do |error|
          assert_instance_of Diagnostic::Ruby::IncompatibleAnnotation, error
          assert_equal :x, error.var_name
        end

        typing.errors.find {|error| error.node == dig(source.node, 1, 2) }.tap do |error|
          assert_instance_of Diagnostic::Ruby::IncompatibleAnnotation, error
          assert_equal :x, error.var_name
        end
      end
    end
  end

  def test_when_typing
    with_checker do |checker|
      source = parse_ruby(<<EOF)
case
when 30
  x = 1
  y = (x + 1).to_int
else
  x = "foo"
  y = (x.to_str).size
end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        pair = construction.synthesize(source.node)

        assert_no_error typing
        assert_equal parse_type("::String | ::Integer"), pair.context.type_env[:x]
        assert_equal parse_type("::Integer"), pair.context.type_env[:y]
      end
    end
  end

  def test_while_typing
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type var x: Integer | String
x = (_ = nil)

while 3
  # @type var x: Integer
  x + 3
end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        pair = construction.synthesize(source.node)

        assert_no_error typing

        typing.source.find_nodes(line: 6, column: 2).tap do |x, *|
          assert_equal parse_type("::Integer"), typing.type_of(node: x)
        end
        assert_equal parse_type("::Integer | ::String"), pair.context.type_env[:x]
      end
    end
  end

  def test_while_type_error
    with_checker do |checker|
      source = parse_ruby(<<EOF)
x = (_ = 3) ? 4 : ""

while true
  x = :foo
end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal 1, typing.errors.size
        assert_instance_of Diagnostic::Ruby::IncompatibleAssignment, typing.errors[0]
      end
    end
  end

  def test_rescue_typing
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type const E: untyped
# @type const F: untyped

begin
  1 + 2
rescue E
  x = 3
  x + 1
rescue F
  # @type var x: String
  x = "foo"
  x + ""
rescue
  x = :foo
end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        pair = construction.synthesize(source.node)

        assert_no_error typing
        assert_equal parse_type("::Integer | ::String | ::Symbol"), pair.type
        assert_equal parse_type("::String | ::Integer | ::Symbol | nil"), pair.context.type_env[:x]
      end
    end
  end

  def test_rescue_binding_typing
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type const E: singleton(String)
# @type const F: singleton(Integer)

begin
  1
rescue E => exn
  exn + ""
rescue F => exn
  exn + 3
end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        pair = construction.synthesize(source.node)

        assert_no_error typing
        assert_equal parse_type("::String | ::Integer"), pair.type
      end
    end
  end

  def test_string_or_true_false
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type var x: String | FalseClass
x = false

# @type var y: String | true
y = true
EOF

      with_standard_construction(checker, source) do |construction, typing|
        _, _, context = construction.synthesize(source.node)

        assert_no_error typing
        assert_equal parse_type("::String | ::FalseClass"), context.type_env[:x]
        assert_equal parse_type("::String | true"), context.type_env[:y]
      end
    end
  end

  def test_type_case_case_when
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type var x: String | Integer | Symbol
x = (_ = nil)

case x
when String
  y = (x + "").size
when Integer
  y = x + 1
else
  y = x.id2name.size
end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        pair = construction.synthesize(source.node)

        assert_no_error typing
        assert_equal parse_type("::Integer"), pair.type
        assert_equal parse_type("::Integer"), pair.constr.context.type_env[:y]
      end
    end
  end

  def test_type_case_case_when_no_body
    with_checker(<<RBS) do |checker|
type ty = String | Array[String] | Integer
RBS
      source = parse_ruby(<<-RUBY)
# @type var x: ty
x = ""

case x
when String, Array
  # nop
else
  x + 1
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        pair = construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_type_case_array1
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type var x: Array[String] | Array[Integer] | Range[Symbol]
x = (_ = nil)

case x
when Array
  y = x[0]
  z = :foo
else
  z = x.begin
end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        pair = construction.synthesize(source.node)

        assert_no_error typing
        assert_equal parse_type("::String | ::Integer | nil"), pair.context.type_env[:y]
        assert_equal parse_type("::Symbol"), pair.context.type_env[:z]
      end
    end
  end

  def test_type_case_array2
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type var x: Array[String] | Array[Integer]
x = (_ = nil)

case x
when Array
  y = x[0]
else
  z = x
end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        pair = construction.synthesize(source.node)

        assert_equal 1, typing.errors.size
        typing.errors[0].yield_self do |error|
          assert_instance_of Diagnostic::Ruby::UnreachableValueBranch, error
          assert_equal error.node, dig(source.node, 1, 2)
        end

        assert_equal parse_type("::String | ::Integer"), pair.type
        assert_nil pair.context.type_env[:z]
      end
    end
  end

  def test_initialize_typing
    with_checker <<-EOF do |checker|
class ABC
  def initialize: (String) -> untyped
end
    EOF
      source = parse_ruby(<<EOF)
class ABC
  def initialize(foo)
  end
end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
      end
    end
  end

  def test_cast_via_underscore
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type var x: String
x = (_ = 3)
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
      end
    end
  end

  def test_parametrized_class_constant
    with_checker do |checker|
      source = parse_ruby(<<EOF)
a = Array.new
EOF

      with_standard_construction(checker, source) do |construction, typing|
        pair = construction.synthesize(source.node)

        assert_empty typing.errors
        assert_equal parse_type("::Array[untyped]"), pair.type
      end
    end
  end

  def test_splat_from_any
    with_checker do |checker|
      source = parse_ruby(<<EOF)
(_ = []).[]=(*(_ = nil))
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_typing_error typing, size: 1 do |errors|
          errors[0].tap do |error|
            assert_instance_of Diagnostic::Ruby::UnsupportedSyntax, error
            assert_equal :splat, error.node.type
          end
        end
      end
    end
  end

  def test_polymorphic
    with_checker <<-EOF do |checker|
class Optional
  def map: [A, B] (A) { (A) -> B } -> B
  def map2: [A, B] (A) { (A) -> B } -> B
end
    EOF
      source = parse_ruby(<<EOF)
class Optional
  def map(x)
    yield x
  end

  def map2(x)
    x.foo
    yield x
  end
end

# @type var x: Optional
x = (_ = nil)
(x.map("foo") {|x| x.size }) + 3
(x.map("foo") {|x| (_ = x) }) + 3
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_typing_error typing, size: 1
        # assert_equal 1, typing.errors.size
        assert_any typing.errors do |error|
          error.is_a?(Diagnostic::Ruby::NoMethod)
        end
      end
    end
  end

  def test_parameterized_class
    with_checker <<-EOF do |checker|
class Container[A]
  @value: A
  def initialize: () -> untyped
  def value: -> A
  def `value=`: (A) -> A
end
    EOF
      source = parse_ruby(<<EOF)
class Container
  def initialize()
  end

  def value
    @value
  end

  def value=(v)
    @value = v
  end
end

# @type var container: Container[Integer]
container = Container.new
container.value = 3
container.value + 4
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_parameterized_module
    with_checker <<-EOF do |checker|
module Value[A]
  @value: A
  def value: -> A
end
    EOF
      source = parse_ruby(<<EOF)
module Value
  def value
    @value
  end
end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
      end
    end
  end

  def test_initialize
    with_checker <<-EOF do |checker|
class HelloWorld
end
    EOF
      source = parse_ruby(<<EOF)
hello = HelloWorld.new
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
      end
    end
  end

  def test_initialize2
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type var hello: Integer
hello = Array.new(3, "")[0]
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_any typing.errors do |error|
          error.is_a?(Diagnostic::Ruby::IncompatibleAssignment) &&
            error.lhs_type == parse_type("::Integer") &&
            error.rhs_type == parse_type("::String")
        end
      end
    end
  end

  def test_initialize_unbound_type_var_fallback_to_any
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type var x: Integer
x = Array.new(3)[0]
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
      end
    end
  end

  def test_if_unwrap
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type var x: Integer?
x = _ = nil

if x
  x + 1
end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
      end
    end
  end

  def test_and_unwrap
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type var x: Integer?
x = _ = nil
# @type var y1: Integer
y1 = 3

z = (x && y1 = y = x + 1)
EOF

      with_standard_construction(checker, source) do |construction, typing|
        pair = construction.synthesize(source.node)

        assert_no_error typing

        assert_equal parse_type("::Integer?"), pair.constr.context.type_env[:y]
        assert_equal parse_type("::Integer?"), pair.constr.context.type_env[:z]
      end
    end
  end

  def test_and_assign
    with_checker do |checker|
      source = parse_ruby(<<EOF)
(x = 1) && (y = 3)
EOF

      with_standard_construction(checker, source) do |construction, typing|
        pair = construction.synthesize(source.node)

        assert_no_error typing

        assert_equal parse_type("::Integer"), pair.context.type_env[:x]
        assert_equal parse_type("::Integer"), pair.context.type_env[:y]
      end
    end
  end

  def test_csend_unwrap
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type var x: String?
x = _ = nil

z = x&.size()
EOF

      with_standard_construction(checker, source) do |construction, typing|
        pair = construction.synthesize(source.node)

        assert_no_error typing

        assert_equal parse_type("::Integer?"), pair.type
        assert_equal parse_type("::Integer?"), pair.context.type_env[:z]
        assert_equal parse_type("::Integer?"), typing.call_of(node: dig(source.node, 1, 1)).return_type
      end
    end
  end

  def test_while
    with_checker do |checker|
      source = parse_ruby(<<EOF)
while line = gets
  x = line
  x.to_str
end
EOF

      with_standard_construction(checker, source, cursor: [2, 2]) do |construction, typing|
        pair = construction.synthesize(source.node)

        assert_empty typing.errors

        assert_equal parse_type("::String"), typing.cursor_context.context.type_env[:line]

        assert_equal parse_type("::String?"), pair.context.type_env[:line]
        assert_equal parse_type("::String?"), pair.context.type_env[:x]
      end
    end
  end

  def test_case_incompatible_annotation
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type var x: String | Integer
x = ""

case x
when String
  # @type var x: Integer
  3
end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        pair = construction.synthesize(source.node)

        assert_equal 1, typing.errors.size

        typing.errors[0].tap do |error|
          assert_instance_of Diagnostic::Ruby::IncompatibleAnnotation, error
          assert_equal dig(source.node, 1, 1, 1), error.node
        end

        assert_equal parse_type("::Integer?"), pair.type
      end
    end
  end

  def test_case_non_exhaustive
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type var x: String | Integer
x = ""

y = case x
when String
  3
end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        pair = construction.synthesize(source.node)

        assert_no_error typing

        assert_equal parse_type("::Integer?"), pair.type
      end
    end
  end

  def test_case_non_exhaustive2
    with_checker do |checker|
      source = parse_ruby(<<EOF)
y = case
    when 1+2
      3
    end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        pair = construction.synthesize(source.node)

        assert_no_error typing
        assert_equal parse_type("::Integer?"), pair.type
      end
    end
  end

  def test_case_exhaustive
    with_checker do |checker|
      source = parse_ruby(<<-RUBY)
# @type var x: String | Integer | Symbol | nil
x = ""

y = case x
    when String
      3
    when Integer
      4
    when Symbol
      5
    when nil
      6
    end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        pair = construction.synthesize(source.node)

        assert_no_error typing
        assert_equal parse_type("::Integer"), pair.type
      end
    end
  end

  def test_case_exhaustive_else
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type var x: String | Integer

y = case (x = "")
when String
  3
else
  4
end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        pair = construction.synthesize(source.node)

        assert_no_error typing

        assert_equal parse_type("::Integer"), pair.type
      end
    end
  end

  def test_def_with_splat_kwargs
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type method f: (**String) -> untyped
def f(**args)
  args[:foo] + "hoge"
end

def g(**xs)
end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)
        assert_all(typing.errors) {|error| error.is_a?(Diagnostic::Ruby::UndeclaredMethodDefinition) }
      end
    end
  end

  def test_splat_kw_args
    with_checker <<-EOF do |checker|
class KWArgTest
  def foo: (Integer, **String) -> void
end
    EOF
      source = parse_ruby(<<EOF)
test = KWArgTest.new

params = { a: 123 }
test.foo(123, **params)
test.foo(123, **123)
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_typing_error(typing, size: 2) do |errors|
          assert_any errors do |error|
            error.is_a?(Diagnostic::Ruby::ArgumentTypeMismatch) &&
              error.actual == parse_type("::Hash[::Symbol, ::Integer]") &&
              error.expected == parse_type("::Hash[::Symbol, ::String]")
          end

          assert_any errors do |error|
            error.is_a?(Diagnostic::Ruby::ArgumentTypeMismatch) &&
              error.actual == parse_type("::Integer") &&
              error.expected == parse_type("::Hash[::Symbol, ::String]")
          end
        end
      end
    end
  end

  def test_block_arg
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type method f: () { (untyped) -> untyped } -> untyped
def f(&block)
end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_and_or
    with_checker do |checker|
      source = parse_ruby(<<EOF)
a = true && false
b = false || true
EOF

      with_standard_construction(checker, source) do |construction, typing|
        pair = construction.synthesize(source.node)

        assert_empty typing.errors

        assert_equal parse_type("false"), pair.context.type_env[:a]
        assert_equal parse_type("true"), pair.context.type_env[:b]
      end
    end
  end

  def test_empty_body_method
    with_checker <<-EOF do |checker|
class EmptyBodyMethod
  def foo: () -> String
end
    EOF
      source = parse_ruby(<<EOF)
class EmptyBodyMethod
  def foo
  end
end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        refute_empty typing.errors
      end
    end
  end

  def test_nil_reject
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type var x: Integer?
x = "x"
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal 1, typing.errors.size
        typing.errors[0].yield_self do |error|
          assert_instance_of Diagnostic::Ruby::IncompatibleAssignment, error
        end
      end
    end
  end

  def test_nil_method
    with_checker do |checker|
      source = parse_ruby(<<EOF)
nil.class
nil.no_such_method
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal 1, typing.errors.size
        typing.errors[0].yield_self do |error|
          assert_instance_of Diagnostic::Ruby::NoMethod, error
          assert_equal :no_such_method, error.method
        end
      end
    end
  end

  def test_optional_method
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type var x: Integer?
x = 3
x.to_s
x.no_such_method
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal 1, typing.errors.size
        typing.errors[0].yield_self do |error|
          assert_instance_of Diagnostic::Ruby::NoMethod, error
          assert_equal :no_such_method, error.method
        end
      end
    end
  end

  def test_literal
    with_checker <<-EOS do |checker|
class ClassWithLiteralArg
  def foo: (123) -> "foo"
         | (Integer) -> :bar
end
    EOS
      source = parse_ruby(<<EOF)
# @type var x: 123
x = 123
a = ClassWithLiteralArg.new.foo(x)
b = ClassWithLiteralArg.new.foo(123)
c = ClassWithLiteralArg.new.foo(1234)
EOF


      with_standard_construction(checker, source) do |construction, typing|
        pair = construction.synthesize(source.node)

        assert_empty typing.errors

        assert_equal parse_type('"foo"'), pair.context.type_env[:a]
        assert_equal parse_type('"foo"'), pair.context.type_env[:b]
        assert_equal parse_type(':bar'), pair.context.type_env[:c]
      end
    end
  end

  def test_literal2
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type var x: 123
x = 123
x + 123

# @type var y: "foo"
y = "foo"
y + "bar"
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
      end
    end
  end

  def test_tuple
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type var x: [Integer, String]
x = (_=[])

a = x[0]
b = x[1]
c = x[2]
EOF

      with_standard_construction(checker, source) do |construction, typing|
        pair = construction.synthesize(source.node)

        assert_no_error typing

        assert_equal parse_type('::Integer'), pair.context.type_env[:a]
        assert_equal parse_type('::String'), pair.context.type_env[:b]
        assert_equal parse_type('::Integer | ::String'), pair.context.type_env[:c]
      end
    end
  end

  def test_tuple1
    with_checker <<-EOF do |checker|
class TupleMethod
  def foo: ([Integer, String]) -> [Integer, String]
end
    EOF
      source = parse_ruby(<<EOF)
# @type var x: [Integer, String]
x = [1, "foo"]
x = ["foo", 1]
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_typing_error(typing, size: 1) do

        end
      end
    end
  end

  def test_tuple2
    with_checker <<-EOF do |checker|
class TupleMethod
  def foo: ([Integer, String]) -> [String, Integer]
end
    EOF
      source = parse_ruby(<<EOF)
x = TupleMethod.new.foo([1, "foo"])
EOF

      with_standard_construction(checker, source) do |construction, typing|
        pair = construction.synthesize(source.node)

        assert_empty typing.errors
        assert_equal parse_type('[::String, ::Integer]'), pair.context.type_env[:x]
      end
    end
  end

  def test_tuple3
    with_checker <<-EOF do |checker|
class TupleMethod
  def foo: () -> [String, Integer, bool]
end
    EOF
      source = parse_ruby(<<EOF)
x, y, z = TupleMethod.new.foo()
a, b = TupleMethod.new.foo()
_, _, _, c = TupleMethod.new.foo()
EOF

      with_standard_construction(checker, source) do |construction, typing|
        pair = construction.synthesize(source.node)

        assert_no_error typing

        assert_equal parse_type('::String'), pair.context.type_env[:x]
        assert_equal parse_type('::Integer'), pair.context.type_env[:y]
        assert_equal parse_type('bool'), pair.context.type_env[:z]

        assert_equal parse_type('::String'), pair.context.type_env[:a]
        assert_equal parse_type('::Integer'), pair.context.type_env[:b]

        assert_equal parse_type("nil"), pair.context.type_env[:c]
      end
    end
  end

  def test_tuple4
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type var x: [Integer, String]
x = [1, "foo"]
x.each do |a|
  a.no_such_method
end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal 1, typing.errors.size
        typing.errors[0].yield_self do |error|
          assert_instance_of Diagnostic::Ruby::NoMethod, error
          assert_equal parse_type("(::Integer | ::String)"), error.type
        end
      end
    end
  end

  def test_tuple5_subtyping
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type var x: [Integer | String, String]
x = [1, "foo"]
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
      end
    end
  end

  def test_tuple_first_last
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type var x: [Integer, String]
x = (_=[])

a = x.first
b = x.last
EOF

      with_standard_construction(checker, source) do |construction, typing|
        _, _, context = construction.synthesize(source.node)

        assert_no_error typing

        assert_equal parse_type('::Integer'), context.type_env[:a]
        assert_equal parse_type('::String'), context.type_env[:b]
      end
    end
  end

  def test_hash_tuple
    with_checker do |checker|
      source = parse_ruby(<<EOF)
hash = { "foo" => 1 }

hash.each do |x|
  a = x[0] + ""
  b = x[1] + 3
end

hash.each do |a, b|
  a + ""
  b + 3
end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_super
    with_checker <<-EOF do |checker|
class TestSuper
  def foo: () -> Integer
end

class TestSuperChild < TestSuper
  def foo: () -> Integer
end
    EOF
      source = parse_ruby(<<EOF)
class TestSuperChild
  def foo
    super + 3
    super() + 1
  end
end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
      end
    end
  end

  def test_super_no_decl
    with_checker <<-EOF do |checker|
class TestSuper
  def foo: () -> Integer
end

class TestSuperChild < TestSuper
end
    EOF
      source = parse_ruby(<<EOF)
class TestSuperChild
  def foo
    super + 3
    super() + 1
  end
end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
      end
    end
  end

  def test_super_missing_required_block
    with_checker <<-EOF do |checker|
class TestSuper
  def initialize: () { () -> nil } -> nil
end

class TestSuperChild < TestSuper
  def initialize: -> void
end
    EOF
      source = parse_ruby(<<EOF)
class TestSuperChild
  def initialize
    super
    super()
  end
end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_typing_error(typing, size: 1) do |errors|
          assert_all!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::RequiredBlockMissing, error
            assert_equal "super", error.location.source
          end
        end
      end
    end
  end

  def test_super_correct_block
    with_checker <<-EOF do |checker|
class TestSuper
  def foo: () { () -> nil } -> nil
end

class TestSuperChild < TestSuper
  def foo: () { () -> nil } -> nil
end
    EOF
      source = parse_ruby(<<EOF)
class TestSuperChild < TestSuper
  def foo
    super do
    end
    super() {}
  end
end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_super_correct_block_called_on_no_block_method
    with_checker <<-EOF do |checker|
class TestSuper
  def foo: () { () -> nil } -> nil
end

class TestSuperChild < TestSuper
  def foo: () -> nil
end
    EOF
      source = parse_ruby(<<EOF)
class TestSuperChild < TestSuper
  def foo
    super do
    end
    super() {}
  end
end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_super_wrong_block
    with_checker <<-EOF do |checker|
class TestSuper
  def initialize: () { () -> nil } -> nil
end

class TestSuperChild < TestSuper
  def initialize: () { () -> nil } -> nil
end
    EOF
      source = parse_ruby(<<EOF)
class TestSuperChild
  def initialize
    super { 42 }
    super() { 42 }
  end
end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_typing_error(typing, size: 2) do |errors|
          assert_all!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::BlockBodyTypeMismatch, error
            assert_equal "{ 42 }", error.location.source
          end
        end
      end
    end
  end

  def test_issue_512
    with_checker <<-EOF do |checker|
module Issue512
  class TestSuper
    def foo: () -> Integer
    def bar: () { (Integer) -> void } -> Integer
  end

  class TestSuperChild < TestSuper
    def foo: () -> Integer
    def bar: () { (Integer) -> void } -> Integer
  end
end
    EOF

      source = parse_ruby(<<-'RUBY')
module Issue512
  class TestSuperChild
    def foo
      super + 3
      super() + 1
    end

    def bar
      super do
      end + 1
      super() {} + 2
    end
  end
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _ = construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_super_missing_super
    with_checker <<-EOF do |checker|
class TestSuper
end

class TestSuperChild < TestSuper
  def bar: () { () -> nil } -> nil
end
    EOF
      source = parse_ruby(<<EOF)
class TestSuperChild
  def bar
    super
    super {} + 1
    super() {} + 2
  end
end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_typing_error(typing, size: 3) do |errors|
          assert_all!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::UnexpectedSuper, error
            assert_equal :bar, error.method
          end
        end
      end
    end
  end

  def test_super_with_block_called_on_no_super_definition
    with_checker <<-EOF do |checker|
class TestNoSuper
  def foo: () -> void
end
    EOF
      source = parse_ruby(<<EOF)
class TestNoSuper
  def foo
    super do
    end
    super() do
    end
    super(42) do
    end
  end
end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_typing_error(typing, size: 3) do |errors|
          assert_all!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::UnexpectedSuper, error
            assert_equal :foo, error.method
          end
        end
      end
    end
  end

  def test_empty_array_is_error
    with_checker do |checker|
      source = parse_ruby(<<EOF)
[]
{}
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal 2, typing.errors.size
        assert_all typing.errors do |error|
          error.is_a?(Diagnostic::Ruby::UnannotatedEmptyCollection)
        end
      end
    end
  end

  def test_alias_hint
    with_checker <<-EOF do |checker|
type a = :foo | :bar
    EOF
      source = parse_ruby(<<EOF)
# @type var a: a
a = :foo
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
      end
    end
  end

  def test_or
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type var x: String?
x = _ = nil
# @type var y: untyped
y = _ = nil

a = x || "foo"
b = "foo" || x
c = y || "foo"
EOF

      with_standard_construction(checker, source) do |construction, typing|
        pair = construction.synthesize(source.node)

        assert_no_error typing
        assert_equal parse_type("::String"), pair.context.type_env[:a]
        assert_equal parse_type("::String"), pair.context.type_env[:b]
        assert_equal parse_type("untyped"), pair.context.type_env[:c]
      end
    end
  end

  def test_hash_optional
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type var x: Hash[Symbol, String?]
x = { foo: "bar" }
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
      end
    end
  end

  def test_array_optional
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type var x: Array[Symbol?]
x = [:foo, :bar]
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_array_union
    with_checker <<EOF do |checker|
class Animal
end

type animal = :dog | :cat
Animal::ALL: Array[animal]
EOF

      source = parse_ruby(<<EOF)
Animal::ALL = [:dog, :cat]
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_passing_empty_block
    with_checker do |checker|
      source = parse_ruby(<<EOF)
x = 1

x.tap {|x| }
x.to_s {|x| }
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_typing_error typing, size: 1 do |errors|
          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::UnexpectedBlockGiven, error
          end
        end
      end
    end
  end

  def test_type_lambda
    with_checker do |checker|
      source = parse_ruby(<<EOF)
-> (x, y) { x }
EOF

      with_standard_construction(checker, source) do |construction, typing|
        type, _ = construction.synthesize(source.node)

        assert_no_error typing
        assert_equal parse_type("^(untyped, untyped) -> untyped"), type
      end
    end
  end

  def test_type_lambda_annotation
    with_checker do |checker|
      source = parse_ruby(<<EOF)
-> (x, y) {
  # @type var x: String
  # @type var y: Integer
  # @type block: :bar
  :foo
}
EOF

      with_standard_construction(checker, source) do |construction, typing|
        type, _ = construction.synthesize(source.node)

        assert_typing_error typing, size: 1
        assert_equal parse_type("^(::String, ::Integer) -> :bar"), type
      end
    end
  end

  def test_type_lambda_hint
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type var proc: ^(String, Integer) -> Symbol
proc = -> (x, y) { :foo }
EOF

      with_standard_construction(checker, source) do |construction, typing|
        type, _ = construction.synthesize(source.node)

        assert_no_error typing
        assert_equal parse_type("^(::String, ::Integer) -> ::Symbol"), type
      end
    end
  end

  def test_type_lambda_hint3
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type var proc: ^(untyped, Integer) -> Symbol
proc = -> (x, y) {
  # @type var x: String
  x + y

  :foo
}
EOF

      with_standard_construction(checker, source) do |construction, typing|
        type, _ = construction.synthesize(source.node)

        assert_typing_error typing, size: 1
        assert_equal parse_type("^(untyped, ::Integer) -> ::Symbol"), type
      end
    end
  end

  def test_type_block_arg
    with_checker <<-EOF do |checker|
class MethodWithBlockArg
  def foo: [X] { (Integer) -> X } -> Array[X]
end
    EOF
      source = parse_ruby(<<EOF)
class MethodWithBlockArg
  def foo(&block)
    [1,2,3].map(&block)
  end
end

a = MethodWithBlockArg.new.foo {|x| x.to_s }
EOF

      with_standard_construction(checker, source) do |construction, typing|
        pair = construction.synthesize(source.node)

        assert_no_error typing
        assert_equal parse_type("::Array[::String]"), pair.context.type_env[:a]
      end
    end
  end

  def test_type_proc_objects
    with_checker <<-EOF do |checker|
class MethodWithBlockArg
  def foo: [X] { (Integer) -> X } -> Array[X]
end
    EOF
      source = parse_ruby(<<EOF)
class MethodWithBlockArg
  def foo(&block)
    block.arity
    [block.call("")]
  end
end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal 1, typing.errors.size
        typing.errors[0].yield_self do |error|
          assert_instance_of Diagnostic::Ruby::ArgumentTypeMismatch, error
        end
      end
    end
  end

  def test_lambda1
    with_checker do |checker|
      source = parse_ruby(<<EOF)
l = -> (x, y) do
  # @type var x: Integer
  x + y
end
EOF

      with_standard_construction(checker, source, cursor: [3, 3]) do |construction, typing|
        pair = construction.synthesize(source.node)

        assert_no_error typing
        assert_equal "^(::Integer, untyped) -> ::Integer", pair.context.type_env[:l].to_s

        lambda_context = typing.cursor_context.context
        assert_equal parse_type("::Integer"), lambda_context.type_env[:x]
        assert_equal parse_type("untyped"), lambda_context.type_env[:y]
      end
    end
  end

  def test_lambda2
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type var l: String
l = -> (x, y) do
  x + y
end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_typing_error(typing, size: 2) do |errors|
          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::IncompatibleAssignment, error
          end
        end
      end
    end
  end

  def test_empty_begin
    with_checker do |checker|
      source = parse_ruby(<<EOF)
a = begin; end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        pair = construction.synthesize(source.node)

        assert_empty typing.errors
        assert_equal parse_type("nil"), pair.type
        assert_equal parse_type("nil"), pair.context.type_env[:a]
      end
    end
  end

  def test_begin_type
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type var a: :foo
a = begin
  :bar
  x = :baz
  y = :foo
end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        pair = construction.synthesize(source.node)

        assert_empty typing.errors
        assert_equal parse_type(":foo"), pair.context.type_env[:a]
        assert_equal parse_type("::Symbol"), pair.context.type_env[:x]
        assert_equal parse_type(":foo"), pair.context.type_env[:y]
      end
    end
  end

  def test_hash_type
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type var x: { id: Integer, name: String }
x = { id: 3, name: "foo" }
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
      end
    end
  end

  def test_hash_type2
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type var x: { id: Integer, name: String }
x = { id: 3, name: :symbol }
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal 1, typing.errors.size
        assert_any typing.errors do |error|
          error.is_a?(Diagnostic::Ruby::IncompatibleAssignment)
        end
      end
    end
  end

  def test_hash_type3
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type var x: { id: Integer, name: String }
x = { id: 3 }
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal 1, typing.errors.size
        assert_any typing.errors do |error|
          error.is_a?(Diagnostic::Ruby::IncompatibleAssignment)
        end
      end
    end
  end

  def test_hash_type4
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type var x: { count: Object }
x = { count: "3" }
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
      end
    end
  end

  def test_hash_type5
    with_checker <<-EOF do |checker|
module WithHashArg
  def self.f: [A] (Hash[Symbol, A]) -> A
end
    EOF
      source = parse_ruby(<<EOF)
WithHashArg.f(foo: 3)
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_hash_union
    with_checker <<EOF do |checker|
class Animal
end

type animal = :dog | :cat
Animal::ALL: Hash[Symbol, animal]
EOF

      source = parse_ruby(<<EOF)
Animal::ALL = { :dog => :dog, :cat => :cat }
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_hash_with_kwargs
    with_checker <<EOF do |checker|
class WithKwargs
  type t = { a: Integer }
  def self.call: (t) -> void
end

EOF

      source = parse_ruby(<<EOF)
WithKwargs.call(a: "123")
WithKwargs.call(a: 123)
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_typing_error(typing, size: 1) do
          assert_any!(typing.errors) do |error|
            assert_instance_of Diagnostic::Ruby::ArgumentTypeMismatch, error
          end
        end
      end
    end
  end

  def test_polymorphic_method
    with_checker <<-EOF do |checker|
interface _Ref[X]
  def get: -> X
end

class Factory[X]
  def initialize: (_Ref[X]) -> untyped
end

class WithPolyMethod
  def foo: [X] (_Ref[X]) -> Factory[X]
end
    EOF
      source = parse_ruby(<<-EOF)
class WithPolyMethod
  def foo(x)
    Factory.new(x)
  end
end
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_array_arg
    with_checker <<-EOF do |checker|
class WithArray
  def foo: (?path: Array[Symbol]) -> void
end
    EOF
      source = parse_ruby(<<-EOF)
WithArray.new.foo(path: [])
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
      end
    end
  end

  def test_private_method1
    with_checker <<-EOF do |checker|
class WithPrivate
  private
  def foo: () -> void
end
    EOF
      source = parse_ruby(<<-EOF)
WithPrivate.new.foo
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_typing_error(typing, size: 1) do |errors|
          assert_any! errors do |error|
            assert_instance_of Diagnostic::Ruby::NoMethod, error
          end
        end
      end
    end
  end

  def test_private_method2
    with_checker <<-EOF do |checker|
class WithPrivate
  def bar: () -> void
  private
  def foo: () -> void
end
    EOF
      source = parse_ruby(<<-EOF)
class WithPrivate
  def foo; end

  def bar
    foo
  end
end
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
      end
    end
  end

  def test_private_method3
    with_checker <<-EOS do |checker|
class WithPrivate
  private
  def foo: () -> void
end
    EOS
      source = parse_ruby(<<-EOF)
class WithPrivate
  def foo; end

  def bar
    self.foo
  end
end
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_typing_error typing, size: 1
      end
    end
  end

  def test_inherit_class
    with_checker <<-EOF do |checker|
class SuperClass
  def foo: () -> Integer
end
    EOF
      source = parse_ruby(<<-EOF)
class ChildClass < SuperClass
  def bar
    foo + ""
  end
end
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_typing_error(typing, size: 3) do |errors|
          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::UnknownConstant, error
          end

          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::UnresolvedOverloading, error
          end
        end
      end
    end
  end

  def test_or_nil_unwrap
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
# @type var x: Array[Integer]?
x = _ = nil
y = x || []
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        pair = construction.synthesize(source.node)

        assert_no_error typing
        assert_equal parse_type("::Array[::Integer]?"), pair.context.type_env[:x]
        assert_equal parse_type("::Array[::Integer]"), pair.context.type_env[:y]
      end
    end
  end

  def test_or_nil_unwrap2
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
# @type var x: Array[Integer]?
# @type var y: Array[Integer]?
# @type var z: Array[Integer]
x = _ = nil
y = _ = nil
z = x || y || []
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        pair = construction.synthesize(source.node)

        assert_no_error typing
        assert_equal parse_type("::Array[::Integer]?"), pair.context.type_env[:x]
        assert_equal parse_type("::Array[::Integer]?"), pair.context.type_env[:y]
        assert_equal parse_type("::Array[::Integer]"), pair.context.type_env[:z]
      end
    end
  end

  def test_alias
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
alias foo bar
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
        assert_equal parse_type("nil"), typing.type_of(node: source.node)
      end
    end
  end

  def test_module_singleton_method_type
    with_checker <<-EOF do |checker|
module WithSingleton
  def self.bar: (Integer) -> void
end
    EOF
      source = parse_ruby(<<-EOF)
module WithSingleton
  def self.bar(x)
    x + 1
  end
end
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)
        assert_empty typing.errors
      end
    end
  end

  def test_module_self_call
    with_checker <<-EOF do |checker|
module Module1
end
    EOF
      source = parse_ruby(<<-EOF)
module Module1
  attr_reader :foo
end
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)
        assert_empty typing.errors
      end
    end
  end

  def test_module_type_mismatch
    with_checker <<-EOF do |checker|
class SampleModule
end
      EOF
      source = parse_ruby(<<-EOF)
module SampleModule
end
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_typing_error(typing, size: 1) do |errors|
          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::ClassModuleMismatch, error
            assert_equal '::SampleModule', error.name.to_s
          end
        end
      end
    end
  end

  def test_class_type_mismatch
    with_checker <<-EOF do |checker|
module SampleClass
end
class SampleModule
end
      EOF
      source = parse_ruby(<<-EOF)
class SampleClass
end
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_typing_error(typing, size: 1) do |errors|
          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::ClassModuleMismatch, error
            assert_equal '::SampleClass', error.name.to_s
          end
        end
      end
    end
  end

  def test_module_no_rbs
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
module SampleModule
  def foo
    self.hello()
  end

  self.world()
end
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_typing_error(typing, size: 4) do |errors|
          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::UnknownConstant, error
          end

          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::NoMethod, error
            assert_equal :hello, error.method
            assert_equal AST::Builtin::BasicObject.instance_type, error.type
          end

          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::NoMethod, error
            assert_equal :world, error.method
            assert_equal AST::Builtin::Module.instance_type, error.type
          end
        end
      end
    end
  end

  def test_class_no_rbs
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
class SampleClass < String
  def foo
    self.hello()
  end

  self.world()
end
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_typing_error(typing, size: 4) do |errors|
          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::UnknownConstant, error
          end

          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::NoMethod, error
            assert_equal :hello, error.method
            assert_equal AST::Builtin::String.instance_type, error.type
          end

          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::NoMethod, error
            assert_equal :world, error.method
            assert_equal AST::Builtin::String.module_type, error.type
          end
        end
      end
    end
  end

  def test_self_call
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
class C1
  attr_reader :baz

  def foo
    to_s
  end
end
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_typing_error(typing, size: 2) do |errors|
          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::UnknownConstant, error
          end
        end
      end
    end
  end

  def test_poly_new
    with_checker <<-EOF do |checker|
class PolyNew[A]
  def initialize: (foo: A) -> void
  def get: -> A
end
    EOF
      source = parse_ruby(<<-EOF)
a = PolyNew.new(foo: "")
b = PolyNew.new(foo: 3)
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)
        assert_empty typing.errors
      end
    end
  end

  def test_context_toplevel
    with_checker <<-EOF do |checker|
    EOF
      source = parse_ruby(<<-EOF)
a = "Hello"
b = 123
      EOF

      with_standard_construction(checker, source, cursor: [0, 0]) do |construction, typing|
        construction.synthesize(source.node)
        assert_empty typing.errors

        # a = ...
        typing.cursor_context.context.tap do |ctx|
          assert_instance_of Context, ctx
          assert_equal construction.module_context, ctx.module_context
          assert_nil ctx.method_context
          assert_nil ctx.block_context
          assert_nil ctx.break_context
          assert_equal parse_type("::Object"), ctx.self_type
        end
      end
    end
  end

  def test_context_class
    with_checker <<-EOF do |checker|
class Hello
end
    EOF
      source = parse_ruby(<<-EOF)
class Hello < Object
  a = "foo"
  b = :bar

  puts
end

b = 123
      EOF

      with_standard_construction(checker, source, cursor: [5, 2]) do |construction, typing|
        construction.synthesize(source.node)
        assert_no_error typing

        # class Hello
        typing.cursor_context.context.tap do |ctx|
          assert_instance_of Context, ctx
          assert_equal "::Hello", ctx.module_context.class_name.to_s
          assert_nil ctx.method_context
          assert_nil ctx.block_context
          assert_nil ctx.break_context
          assert_equal parse_type("singleton(::Hello)"), ctx.self_type
          assert_equal parse_type("::String"), ctx.type_env[:a]
          assert_equal parse_type("::Symbol"), ctx.type_env[:b]
        end
      end
    end
  end

  def test_return_type
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
return 3
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)
        assert_empty typing.errors

        assert_instance_of Steep::AST::Types::Bot, typing.type_of(node: source.node)
      end
    end
  end

  def test_begin_void
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
1+2
return 3
x = 4
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)
        assert_empty typing.errors

        assert_instance_of Steep::AST::Types::Bot, typing.type_of(node: source.node)
      end
    end
  end

  def test_assign_send_arg
    with_checker <<-EOF do |checker|
class AssignTest
  def foo: (*untyped) -> void
end
    EOF
      source = parse_ruby(<<-RUBY)
AssignTest.new.foo(a = 1, b = a+1)
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        _, _, context = construction.synthesize(source.node)

        assert_no_error typing

        assert_equal parse_type("::Integer"), context.type_env[:a]
        assert_equal parse_type("::Integer"), context.type_env[:b]
      end
    end
  end

  def test_assign_csend_arg
    with_checker <<-EOF do |checker|
class AssignTest
  def foo: (*untyped) -> void
end
    EOF
      source = parse_ruby(<<-RUBY)
# @type var test: AssignTest?
test = _ = nil
test&.foo(x = "", y = x)
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        _, _, context = construction.synthesize(source.node)

        assert_no_error typing

        assert_equal parse_type("::String?"), context.type_env[:x]
        assert_equal parse_type("::String?"), context.type_env[:y]
      end
    end
  end

  def test_if_return_2
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
a = [3, nil][0]
if a
  puts
else
  return
end

a + 1
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)
        assert_no_error typing
      end
    end
  end

  def test_unless_return
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
a = [3, nil][0]
return unless a

a + 1
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)
        assert_no_error typing
      end
    end
  end

  def test_and_occurrence
    with_checker do |checker|
      source = parse_ruby(<<EOF)
(x = [1,nil][0]) && x + 1

y = x and return
EOF

      with_standard_construction(checker, source) do |construction, typing|
        _, _, context = construction.synthesize(source.node)

        assert_no_error typing

        assert_equal parse_type("nil"), context.type_env[:x]
        assert_equal parse_type("nil"), context.type_env[:y]
      end
    end
  end

  def test_or_occurrence
    with_checker do |checker|
      source = parse_ruby(<<EOF)
x = [1,nil][0]
y = x
y or return
EOF

      with_standard_construction(checker, source) do |construction, typing|
        _, _, context = construction.synthesize(source.node)

        assert_no_error typing

        assert_equal parse_type("::Integer?"), context.type_env[:x]
        assert_equal parse_type("::Integer"), context.type_env[:y]
      end
    end
  end

  def test_heredoc
    with_checker do |checker|
      source = parse_ruby(<<'EOF')
q = <<-QUERY
  #{[1].map { "" }}
QUERY
q
EOF

      with_standard_construction(checker, source) do |construction, typing|
        _, _, context = construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_casgn_in_nested_class
    with_checker <<EOF do |checker|
class A
end

class A::B
end

A::B::C: Array[String]
EOF
      source = parse_ruby(<<RUBY)
class A::B
  C = []
  # @type var x: Array[String]
  x = C
end

class A
  class B
    C = []
    # @type var x: Array[String]
    x = C
  end
end

A::B::C = []
# @type var x: Array[String]
x = A::B::C
RUBY

      with_standard_construction(checker, source) do |construction, typing|
        _, _, context = construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_singleton_class_in_class_decl
    with_checker <<-RBS do |checker|
class WithSingleton
  def self.open: [A] { (WithSingleton) -> A } -> A
end
    RBS
      source = parse_ruby(<<'EOF')
class WithSingleton
  class <<self
    def open
      yield new()
    end
  end
end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        class_constr = construction.for_class(source.node, RBS::TypeName.parse("::WithSingleton"), nil)
        type, _ = class_constr.synthesize(dig(source.node, 2, 0))
        sclass_constr = class_constr.for_sclass(dig(source.node, 2), type)

        module_context = sclass_constr.context.module_context

        assert_equal parse_type("singleton(::WithSingleton)"), module_context.instance_type
        assert_equal parse_type("::Class"), module_context.module_type
        assert_equal "::WithSingleton", module_context.class_name.to_s
        assert_nil module_context.implement_name
        assert_nil module_context.module_definition
        assert_equal "::WithSingleton", module_context.instance_definition.type_name.to_s

        construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_singleton_class_in_class_decl_error
    with_checker <<-RBS do |checker|
class WithSingleton
  def self.open: [A] { (instance) -> A } -> A
end
    RBS
      source = parse_ruby(<<'EOF')
class WithSingleton
  class <<self
    def open
      yield 30
    end
  end
end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal 1, typing.errors.size
        assert_instance_of Diagnostic::Ruby::ArgumentTypeMismatch, typing.errors[0]
      end
    end
  end

  def test_singleton_class_for_object_success
    with_checker <<-'RBS' do |checker|
class WithSingleton
  def open: [A] (Integer) { (WithSingleton, Integer) -> A } -> A
end
    RBS
      source = parse_ruby(<<-'RUBY')
class <<(WithSingleton.new)
  def open(i)
    yield WithSingleton.new(), i+1
  end
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _ = construction.synthesize(dig(source.node, 0))
        sclass_constr = construction.for_sclass(dig(source.node), type)

        module_context = sclass_constr.context.module_context

        assert_equal parse_type("::WithSingleton"), module_context.instance_type
        assert_equal parse_type("singleton(::WithSingleton)"), module_context.module_type
        assert_equal RBS::TypeName.parse("::Object"), module_context.class_name
        assert_nil module_context.implement_name
        assert_equal RBS::TypeName.parse("::WithSingleton"), module_context.module_definition.type_name
        assert_equal RBS::TypeName.parse("::WithSingleton"), module_context.instance_definition.type_name

        construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_singleton_class_for_object_type_check
    with_checker <<-'RBS' do |checker|
class WithSingleton
  def open: [A] { () -> A } -> A
end
    RBS
      source = parse_ruby(<<-'RUBY')
class <<(WithSingleton.new)
  def open(x)
    x
  end
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_typing_error typing, size: 1 do |errors|
          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::MethodParameterMismatch, error
          end
        end
      end
    end
  end

  def test_literal_typing_with_hint
    with_checker <<-'RBS' do |checker|
type a = 1 | 2 | 3
type b = "x" | "y" | "z"

type c = a | b
    RBS
      source = parse_ruby(<<-'RUBY')
# @type var c: c

c = 1
c = "x"
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_tuple_typing
    with_checker <<-'RBS' do |checker|
type t = [String]
    RBS
      source = parse_ruby(<<-'RUBY')
# @type var a: [Integer]?
a = [1]

# @type var b: t
b = ["a"]

# @type var c: t?
c = ["b"]

# @type var d: [Integer] | t
d = ["a"]
d = [1]
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_class_variables
    with_checker <<-'RBS' do |checker|
class Object
  def ==: (untyped) -> bool
end

class TypeVariable
  @@index: Integer
  attr_reader name: String

  def initialize: (String name) -> void

  def self.fresh: () -> instance

  def last?: () -> bool
end
    RBS
      source = parse_ruby(<<-'RUBY')
class TypeVariable
  @@index = 0

  def name
    @name
  end

  def initialize(name)
    @name = name
  end

  def last?
    name == "#{@@index}"
  end

  def self.fresh
    @@index += 1

    new("#{@@index}")
  end
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_class_variables_error
    with_checker <<-'RBS' do |checker|
class TypeVariable
  @@index: Integer
end
    RBS
      source = parse_ruby(<<-'RUBY')
class TypeVariable
  @@no_error = @@unknown_error2

  @@index = ""
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal 3, typing.errors.size

        assert_any!(typing.errors) do |error|
          assert_instance_of Diagnostic::Ruby::FallbackAny, error
          assert_equal :cvasgn, error.node.type
        end

        assert_any!(typing.errors) do |error|
          assert_instance_of Diagnostic::Ruby::FallbackAny, error
          assert_equal :cvar, error.node.type
        end

        assert_any!(typing.errors) do |error|
          assert_instance_of Diagnostic::Ruby::IncompatibleAssignment, error
          assert_equal :cvasgn, error.node.type
        end
      end
    end
  end

  def test_flow_sensitive_untyped
    with_checker do |checker|
      source = parse_ruby(<<-RUBY)
def preserve_empty_line(prev, decl)
  decl = 1 unless prev

  prev.foo
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_count!(typing.errors, 1) do |error|
          assert_instance_of Diagnostic::Ruby::UndeclaredMethodDefinition, error
        end
      end
    end
  end

  def test_flow_sensitive_if_return
    with_checker(<<-RBS) do |checker|
class OptionalBlockParam
  def foo: { (Integer?) -> void } -> void
end
    RBS

      source = parse_ruby(<<-RUBY)
OptionalBlockParam.new.foo do |x|
  next unless x
  x + 1
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)
        assert_no_error typing
      end
    end
  end

  def test_flow_sensitive_when_optional
    with_checker(<<-RBS) do |checker|
class FlowSensitiveOptional
  def foo: (bar: String) -> void
         | (baz: Integer) -> void
end
    RBS
      source = parse_ruby(<<-RUBY)
class FlowSensitiveOptional
  def foo(bar: nil, baz: nil)
    case
    when bar
      bar + ""
    when baz
      baz + 3
    end
  end
end

      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_flow_sensitive_when
    with_checker do |checker|
      source = parse_ruby(<<-RUBY)
array = [1,2,3]
case
when (number = array.first).nil?
  # number is nil
else
  # number is Integer
  number + 100
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_flow_sensitive_when2
    with_checker do |checker|
      source = parse_ruby(<<-RUBY)
array = [1,2,3]
a = array.first
b = array.first

case
when a.nil?
  :a
when b.nil?
  :c
else
  a + b
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _ = construction.synthesize(source.node)

        assert_no_error typing
        assert_equal parse_type("::Symbol | ::Integer"), type
      end
    end
  end

  def test_orasign_lvar
    with_checker do |checker|
      source = parse_ruby(<<-RUBY)
# @type var y: String

x = (_ = 1) ? "" : nil
x ||= ""
y = x
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_orasign_ivar
    with_checker <<-RBS do |checker|
class IVar
  @ivar: String?

  def set: () -> String
end
    RBS
      source = parse_ruby(<<-RUBY)
class IVar
  def set
    @ivar ||= "foo"
  end
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_orasgn_call
    with_checker do |checker|
      source = parse_ruby(<<-RUBY)
a = [1,2,3]

a[0] ||= 3
a[1] &&= 4
        RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_numbers_numeric
    with_checker do |checker|
      source = parse_ruby(<<-RUBY)
# @type var x: [Numeric]
x = [1]
x = [1.0]
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_void_hint
    with_checker(<<-RBS) do |checker|
class VoidHint
  def foo: { () -> void } -> void
  def bar: () -> void
end
    RBS
      source = parse_ruby(<<-RUBY)
class VoidHint
  def bar
    foo {
      # @type var x: :foo
      x = :foo
    }
  end

  def foo
  end
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_case_when_union
    with_checker(<<-RBS) do |checker|
class WhenUnion
  def map: [A] (A) -> A
end
    RBS
      source = parse_ruby(<<-RUBY)
x = WhenUnion.new.map(case _ = 1
  when String
    "foo"
  else
    3
  end
)
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        _, _, context = construction.synthesize(source.node)

        assert_no_error typing
        assert_equal parse_type("::Integer | ::String"), context.type_env[:x]
      end
    end
  end

  def test_endless_range
    with_checker(<<-RBS) do |checker|
    RBS
      source = parse_ruby(<<-RUBY)
a = 1..
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        _, _, context = construction.synthesize(source.node)

        assert_no_error typing
        assert_equal parse_type("::Range[::Integer?]"), context.type_env[:a]
      end
    end
  end

  def test_generic_param_rename
    with_checker(<<-RBS) do |checker|
interface _Hello[A]
  def get: [A] () -> A
end

class TestTest[A]
  def foo: (_Hello[A]) -> void
end
    RBS
      source = parse_ruby(<<-RUBY)
class TestTest
  def foo(x)
   x.get()
  end
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)
        assert_no_error typing
      end
    end
  end

  def test_module_method_call
    with_checker(<<-RBS) do |checker|
module Types
  def foo: () -> String
  def hash: () -> String
end

class Object
  def hash: () -> Integer
end
    RBS
      source = parse_ruby(<<-RUBY)
module Types
  def foo
    hash + "a"
  end

  def hash
    "foo"
  end
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)
        assert_no_error typing
      end
    end
  end

  def test_sclass_no_sig
    with_checker(<<-RBS) do |checker|
    RBS
      source = parse_ruby(<<-RUBY)
class SClassNoSig
  class << self
  end
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_typing_error(typing, size: 1) do |errors|
          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::UnknownConstant, error
            assert_equal :SClassNoSig, error.name
          end
        end
      end
    end
  end

  def test_assign_untyped_singleton_class
    with_checker do |checker|
      source = parse_ruby(<<-'RUBY')
# @type var unknown: untyped
unknown = _ = BasicObject.new
_sclass = class << unknown
  self
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        _, _, context = construction.synthesize(source.node)

        assert_typing_error typing, size: 1 do |errors|
          assert_all!(typing.errors) do |error|
            assert_instance_of Diagnostic::Ruby::UnsupportedSyntax, error
          end
        end

        assert_equal parse_type("nil"), context.type_env[:_sclass]
      end
    end
  end

  def test_block_param_masgn
    with_checker(<<-RBS) do |checker|
class BlockParamTuple
  def foo: () { ([Integer, String]) -> void } -> void
end
    RBS
      source = parse_ruby(<<-RUBY)
BlockParamTuple.new.foo do |(x, y)|
  x + 1
  y + ""
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)
        assert_no_error typing
      end
    end
  end

  def test_logic_receiver_is_nil
    with_checker(<<-RBS) do |checker|
    RBS
      source = parse_ruby(<<-RUBY)
a = [1].first
return if a.nil?
a + 1

b = [1].first
return if (x = b).nil?
x + 1

c = [1].first
return if (y = c.nil?)
c + 1

d = [1].first
puts "nil!" and return if d.nil?
d + 1

e = [1].first
nil or return if e.nil?
e + 1
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)
        assert_no_error typing
      end
    end
  end

  def test_logic_receiver_is_arg
    with_checker(<<-RBS) do |checker|
    RBS
      source = parse_ruby(<<-RUBY)
a = [1, ""].first

return if a.nil?

if a.is_a?(String)
  a + "!"
else
  a + 1
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)
        assert_no_error typing
      end
    end
  end

  def test_logic_arg_is_receiver
    with_checker(<<-RBS) do |checker|
    RBS
      source = parse_ruby(<<-RUBY)
a = [1, ""].first

return if a.nil?

if String === a
  a + "!"
else
  a + 1
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)
        assert_no_error typing
      end
    end
  end

  def test_logic_value
    with_checker(<<-RBS) do |checker|
    RBS
      source = parse_ruby(<<-RUBY)
a = [1].first
return unless a
a+1
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)
        assert_no_error typing
      end
    end
  end

  def test_logic_not
    with_checker(<<-RBS) do |checker|
    RBS
      source = parse_ruby(<<-RUBY)
a = [1].first
return if !a
a+1
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)
        assert_no_error typing
      end
    end
  end

  def test_logic_not2
    with_checker(<<-RBS) do |checker|
    RBS
      source = parse_ruby(<<-RUBY)
a = !Object.new
a || true
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)
        assert_no_error typing
      end
    end
  end

  def test_logic_and
    with_checker(<<-RBS) do |checker|
    RBS
      source = parse_ruby(<<-RUBY)
a = [1].first
a.nil? and return
a + 1
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)
        assert_no_error typing
      end
    end
  end

  def test_logic_or
    with_checker(<<-RBS) do |checker|
    RBS
      source = parse_ruby(<<-RUBY)
a = [1].first
!a.nil? or return
a + 1
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)
        assert_no_error typing
      end
    end
  end

  def test_logic_type_no_escape
    with_checker(<<-RBS) do |checker|
    RBS
      source = parse_ruby(<<-RUBY)
a = [1].first
x = a.nil?
return if _ = x
a + 1
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)
        assert_equal 1, typing.errors.size
      end
    end
  end

  def test_logic_type_no_escape2
    with_checker(<<-RBS) do |checker|
class Object
  def yield_self: [A] () { () -> A } -> A
end
    RBS
      source = parse_ruby(<<-RUBY)
a = [1].first
return unless a.yield_self { !a.nil? }
a + 1
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_typing_error(typing, size: 1) do |errors|
          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::NoMethod, error
          end
        end
      end
    end
  end

  def test_logic_type_case_any
    with_checker(<<-RBS) do |checker|
    RBS
      source = parse_ruby(<<-RUBY)
a = _ = 3

a.foooooooooooooo

if a.is_a?(String)
  a.fooooooo
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)
        assert_equal 1, typing.errors.size
      end
    end
  end

  def test_type_case_after_union
    with_checker(<<-RBS) do |checker|
    RBS
      source = parse_ruby(<<-RUBY)
x = [1, ""].first

case x
when String
  x + ""
end

x + ""       # <= error! (x: String | Integer | nil)
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)
        assert_typing_error typing, size: 1
      end
    end
  end

  def test_type_case_after_any
    with_checker(<<-RBS) do |checker|
    RBS
      source = parse_ruby(<<-RUBY)
x = _ = nil

case x
when String
  x + 1     # <= error! (x: String)
end

x + 2       # <= no error (x: untyped)
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)
        assert_equal 1, typing.errors.size
      end
    end
  end

  def test_incompatible_annotation
    with_checker(<<-RBS) do |checker|
    RBS
      source = parse_ruby(<<-RUBY)
x = _ = nil

case x
when String
  # @type var x: Integer
  x + 1
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_typing_error typing, size: 1
        assert_instance_of Diagnostic::Ruby::IncompatibleAnnotation, typing.errors[0]
      end
    end
  end

  def test_case_when_flow_sensitive_bug
    with_checker(<<-RBS) do |checker|
    RBS
      source = parse_ruby(<<-RUBY)
# @type var version: String?
version = _ = nil
# @type var optional_path: String?
optional_path = _ = nil

case
when !version && path = optional_path
  path + ""
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_rescue_hint
    with_checker(<<-RBS) do |checker|
    RBS
      source = parse_ruby(<<-RUBY)
# @type var x: [Integer, String]
x = begin
      [1, ""]
    rescue
      [2, ""]
    end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)
        assert_no_error typing
      end
    end
  end

  def test_module_attribute
    with_checker(<<-RBS) do |checker|
class Module
  attr_accessor hello: String
end
    RBS
      source = parse_ruby(<<-RUBY)
Object.new
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)
        assert_no_error typing
      end
    end
  end

  def test_type_case_interface
    with_checker(<<-RBS) do |checker|
interface _Fooable
end

class WithName
  attr_reader name: String
end

class WithEmail
  attr_reader email: String
end
    RBS
      source = parse_ruby(<<-RUBY)
# @type var x: _Fooable
x = _ = nil

case x
when WithName
  x.name
when WithEmail
  x.email
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)
        assert_no_error typing
      end
    end
  end

  def test_flow_sensitive_and
    with_checker(<<-RBS) do |checker|
class Fun
  def foo: (Integer?) -> void
  def foo2: (Integer) -> void
end
    RBS
      source = parse_ruby(<<-RUBY)
class Fun
  def foo(v)
    !v.nil? && foo2(v)
  end

  def foo2(_)
  end
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)
        assert_no_error typing
      end
    end
  end

  def test_assignment_call
    with_checker(<<-RBS) do |checker|
class Fun
  def foo=: (Integer) -> String
  def []=: (Integer, String) -> Symbol
end
    RBS
      source = parse_ruby(<<-RUBY)
# @type var x: Integer
x = Fun.new.foo = 30
# @type var y: String
y = Fun.new[1] = "hoge"
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)
        assert_no_error typing
      end
    end
  end

  def test_send_untyped
    with_checker() do |checker|
      source = parse_ruby(<<-RUBY)
a = _ = nil
x = a.foo(1)
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        _, constr = construction.synthesize(source.node)

        assert_no_error typing

        dig(source.node, 1, 1).tap do |node|
          # a.foo(1)
          call = typing.call_of(node: node)
          assert_instance_of MethodCall::Untyped, call
        end

        assert_equal parse_type("untyped"), constr.context.type_env[:x]
        assert_equal parse_type("::Integer"), typing.type_of(node: dig(source.node, 1, 1, 2))
      end
    end
  end

  def test_send_top_void
    with_checker() do |checker|
      source = parse_ruby(<<-RUBY)
# @type var a: top
a = _ = nil
x = a.foo(1)

# @type var b: void
b = _ = nil
y = b.foo(2)
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        _, constr = construction.synthesize(source.node)

        dig(source.node, 1, 1).tap do |a_foo|
          error = typing.errors.find {|error| error.node == a_foo }
          assert_instance_of Diagnostic::Ruby::NoMethod, error

          call = typing.call_of(node: a_foo)
          assert_instance_of MethodCall::NoMethodError, call
        end

        dig(source.node, 3, 1).tap do |b_foo|
          error = typing.errors.find {|error| error.node == b_foo }
          assert_instance_of Diagnostic::Ruby::NoMethod, error

          call = typing.call_of(node: b_foo)
          assert_instance_of MethodCall::NoMethodError, call
        end

        assert_equal parse_type("untyped"), constr.context.type_env[:x]
        assert_equal parse_type("untyped"), constr.context.type_env[:y]

        assert_equal parse_type("::Integer"), typing.type_of(node: dig(source.node, 1, 1, 2))
        assert_equal parse_type("::Integer"), typing.type_of(node: dig(source.node, 3, 1, 2))
      end
    end
  end

  def test_send_concrete_receiver
    with_checker(<<RBS) do |checker|
class SendTest
  def foo: (Integer) -> String
end
RBS
      source = parse_ruby(<<-RUBY)
x = SendTest.new().foo(1)
y = SendTest.new().foo("1")
z = SendTest.new().foo()
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        _, constr = construction.synthesize(source.node)

        assert_equal 2, typing.errors.size

        dig(source.node, 0, 1).tap do |call_node|
          call = typing.call_of(node: call_node)
          assert_instance_of MethodCall::Typed, call
        end

        dig(source.node, 1, 1).tap do |call_node|
          call = typing.call_of(node: call_node)
          assert_instance_of MethodCall::Error, call

          assert_equal 1, call.errors.size
          assert_instance_of Diagnostic::Ruby::ArgumentTypeMismatch, call.errors[0]
        end

        dig(source.node, 2, 1).tap do |call_node|
          call = typing.call_of(node: call_node)
          assert_instance_of MethodCall::Error, call

          assert_equal 1, call.errors.size
          assert_instance_of Diagnostic::Ruby::InsufficientPositionalArguments, call.errors[0]
        end

        assert_equal parse_type("::String"), constr.context.type_env[:x]
        assert_equal parse_type("::String"), constr.context.type_env[:y]
        assert_equal parse_type("::String"), constr.context.type_env[:z]
      end
    end
  end

  def test_send_concrete_receiver_with_block
    with_checker(<<RBS) do |checker|
class SendTest
  def foo: (Integer) { (Integer) -> void } -> String
end
RBS
      source = parse_ruby(<<-RUBY)
# @type var test: SendTest
test = _ = nil

x = test.foo(1) do
end

y = SendTest.new().foo("1") do
end

z = SendTest.new().foo() do
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        _, constr = construction.synthesize(source.node)

        assert_equal 2, typing.errors.size

        dig(source.node, 1, 1).tap do |call_node|
          call = typing.call_of(node: call_node)
          assert_instance_of MethodCall::Typed, call
        end

        dig(source.node, 2, 1).tap do |call_node|
          call = typing.call_of(node: call_node)
          assert_instance_of MethodCall::Error, call

          assert_equal 1, call.errors.size
          assert_instance_of Diagnostic::Ruby::ArgumentTypeMismatch, call.errors[0]
        end

        dig(source.node, 3, 1).tap do |call_node|
          call = typing.call_of(node: call_node)
          assert_instance_of MethodCall::Error, call

          assert_equal 1, call.errors.size
          assert_instance_of Diagnostic::Ruby::InsufficientPositionalArguments, call.errors[0]
        end

        assert_equal parse_type("::String"), constr.context.type_env[:x]
        assert_equal parse_type("::String"), constr.context.type_env[:y]
        assert_equal parse_type("::String"), constr.context.type_env[:z]
      end
    end
  end

  def test_send_concrete_receiver_without_expected_block
    with_checker(<<RBS) do |checker|
class SendTest
  def foo: (Integer) { (Integer) -> void } -> String
end
RBS
      source = parse_ruby(<<-RUBY)
# @type var test: SendTest
test = _ = nil

x = test.foo(1)
y = test.foo("1")
z = test.foo()
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        _, constr = construction.synthesize(source.node)

        # assert_no_error typing

        # assert_equal 4, typing.errors.size

        dig(source.node, 1, 1).tap do |call_node|
          call = typing.call_of(node: call_node)
          assert_instance_of MethodCall::Error, call

          assert_equal 1, call.errors.size
          assert_instance_of Diagnostic::Ruby::RequiredBlockMissing, call.errors[0]
        end

        dig(source.node, 2, 1).tap do |call_node|
          call = typing.call_of(node: call_node)
          assert_instance_of MethodCall::Error, call

          assert_equal 2, call.errors.size
        end

        dig(source.node, 3, 1).tap do |call_node|
          call = typing.call_of(node: call_node)
          assert_instance_of MethodCall::Error, call

          assert_equal 2, call.errors.size
          assert_any!(call.errors) do |error|
            assert_instance_of Diagnostic::Ruby::RequiredBlockMissing, error
          end
          assert_any!(call.errors) do |error|
            assert_instance_of Diagnostic::Ruby::InsufficientPositionalArguments, error
          end
        end

        assert_equal parse_type("::String"), constr.context.type_env[:x]
        assert_equal parse_type("::String"), constr.context.type_env[:y]
        assert_equal parse_type("::String"), constr.context.type_env[:z]
      end
    end
  end

  def test_send_concrete_receiver_without_expected_block_type_var
    with_checker(<<RBS) do |checker|
class SendTest
  def foo: [A] () { (Integer) -> A } -> Array[A]
  def bar: [A] (A) { () -> A } -> Array[A]
end
RBS
      source = parse_ruby(<<-RUBY)
# @type var test: SendTest
test = _ = nil

x = test.foo()           # Without any constraints on A
y = test.bar("foo")      # With a constraint: String <: A
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        _, constr = construction.synthesize(source.node)

        assert_equal 2, typing.errors.size

        dig(source.node, 1, 1).tap do |call_node|
          call = typing.call_of(node: call_node)
          assert_instance_of MethodCall::Error, call

          assert_equal parse_type("::Array[untyped]"), call.return_type

          assert_equal 1, call.errors.size
          assert_instance_of Diagnostic::Ruby::RequiredBlockMissing, call.errors[0]
        end

        dig(source.node, 2, 1).tap do |call_node|
          call = typing.call_of(node: call_node)
          assert_instance_of MethodCall::Error, call

          assert_equal parse_type("::Array[::String]"), call.return_type

          assert_equal 1, call.errors.size
        end
      end
    end
  end

  def test_send_concrete_receiver_with_unsupported_block_params
    with_checker(<<RBS) do |checker|
class SendTest
  def foo: [A] () { (Integer, String) -> A } -> Array[A]
end

class ::Integer
  def to_a: () -> [Integer]
end
RBS
      source = parse_ruby(<<-RUBY)
# @type var test: SendTest
test = _ = nil

test.foo do |(x, y), z|
  x.type_of_x
  y.type_of_y
  z.type_of_z
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        _, constr = construction.synthesize(source.node)

        assert_typing_error typing, size: 3 do |errors|
          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::NoMethod, error
            assert_equal parse_type("::Integer"), error.type
            assert_equal :type_of_x, error.method
          end
          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::NoMethod, error
            assert_equal parse_type("nil"), error.type
            assert_equal :type_of_y, error.method
          end
          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::NoMethod, error
            assert_equal parse_type("::String"), error.type
            assert_equal :type_of_z, error.method
          end
        end
      end
    end
  end

  def test_send_concrete_receiver_no_block_method_with_blockarg
    with_checker(<<RBS) do |checker|
class SendTest
  def foo: () -> String
end
RBS
      source = parse_ruby(<<-RUBY)
# @type var test: SendTest
test = _ = nil

test.foo(&->(x) { "" })
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        _, constr = construction.synthesize(source.node)

        assert_equal 1, typing.errors.size

        dig(source.node, 1).tap do |call_node|
          call = typing.call_of(node: call_node)
          assert_instance_of MethodCall::Error, call

          assert_equal parse_type("::String"), call.return_type

          assert_equal 1, call.errors.size
          assert_instance_of Diagnostic::Ruby::UnexpectedBlockGiven, call.errors[0]
        end
      end
    end
  end

  def test_send_concrete_receiver_receiving_block_with_blockarg
    with_checker(<<RBS) do |checker|
class SendTest
  def foo: () { (Integer) -> String }-> String
end
RBS
      source = parse_ruby(<<-RUBY)
# @type var test: SendTest
test = _ = nil

test.foo(&->(x) { "" })

# @type var p: ^(::Integer, ::String) -> ::String
p = -> (x, y) { "" }
test.foo(&p)
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        _, constr = construction.synthesize(source.node)

        assert_equal 1, typing.errors.size

        dig(source.node, 1).tap do |call_node|
          call = typing.call_of(node: call_node)
          assert_instance_of MethodCall::Typed, call

          assert_equal parse_type("::String"), call.return_type
        end

        dig(source.node, 3).tap do |call_node|
          call = typing.call_of(node: call_node)
          assert_instance_of MethodCall::Error, call

          assert_equal parse_type("::String"), call.return_type

          assert_equal 1, call.errors.size
          assert_instance_of Diagnostic::Ruby::BlockTypeMismatch, call.errors[0]
        end
      end
    end
  end

  def test_block_pass_and_untyped
    with_checker(<<-RBS) do |checker|
interface _YieldUntyped
  def m: [T] () { (untyped) -> T } -> T
end
    RBS
      source = parse_ruby(<<-EOF)
# @type var x: _YieldUntyped
x = (_ = nil)
r = x.m(&:to_s)
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        pair = construction.synthesize(source.node)

        assert_no_error typing

        assert_equal parse_type("::_YieldUntyped"), pair.context.type_env[:x]
        assert_equal parse_type("untyped"), pair.context.type_env[:r]
      end
    end
  end

  def test_block_pass_and_method__valid
    with_checker(<<-RBS) do |checker|
class Object
  def method: (Symbol) -> Method
  def my_to_s: (Integer) -> String
end

class Method
end
    RBS
      source = parse_ruby(<<-EOF)
x = [1, 2, 3]
r = x.map(&method(:my_to_s))
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        pair = construction.synthesize(source.node)

        assert_no_error typing

        assert_equal parse_type("::Array[::String]"), pair.context.type_env[:r]
      end
    end
  end

  def test_block_pass_and_method__invalid
    with_checker(<<-RBS) do |checker|
class Object
  def method: (Symbol) -> Method
  def my_to_s: (String) -> String
end

class Method
end
    RBS
      source = parse_ruby(<<-EOF)
x = [1, 2, 3]
r = x.map(&method(:my_to_s))
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        pair = construction.synthesize(source.node)

        assert_typing_error typing, size: 1 do |errors|
          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::BlockTypeMismatch, error
            assert (/^\^\(::Integer\) -> X\(\d+\)$/ =~ error.expected.to_s)
            assert_equal parse_type("^(::String) -> ::String"), error.actual
          end
        end

        assert_equal parse_type("::Array[untyped]"), pair.context.type_env[:r]
      end
    end
  end

  def test_send_unsatisfiable_constraint
    with_checker(<<RBS) do |checker|
class SendTest
  def foo: [A, B] (A) { (A) -> void } -> B
end
RBS
      source = parse_ruby(<<-RUBY)
# @type var test: SendTest
test = _ = nil

test.foo([]) do |x|
  # @type var x: String
  x.foo()
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _ = construction.synthesize(source.node)

        assert_typing_error typing, size: 2 do |errors|
          assert_instance_of Diagnostic::Ruby::NoMethod, errors[0]
          assert_instance_of Diagnostic::Ruby::UnsatisfiableConstraint, errors[1]
        end

        assert_equal parse_type("untyped"), type
      end
    end
  end

  def test_send_rbs_error
    with_checker(<<RBS) do |checker|
class SendTest
  def foo: () -> String123
end
RBS
      source = parse_ruby(<<-RUBY)
# @type var test: SendTest
test = _ = nil

test.foo
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _ = construction.synthesize(source.node)

        assert_typing_error typing, size: 1 do |error,|
          assert_instance_of Diagnostic::Ruby::UnexpectedError, error
          assert_instance_of RBS::NoTypeFoundError, error.error
        end

        assert_equal parse_type("untyped"), type
      end
    end
  end

  def test_const
    with_checker(<<RBS) do |checker|
class Nested
  module Consta
    class Nt
    end
  end
end
RBS
      source = parse_ruby(<<-RUBY)
::Nested::Consta::Nt
Nested::Consta::Nt = _ = 30
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        typing.type_of(node: dig(source.node, 0, 0, 0, 0))
        typing.type_of(node: dig(source.node, 0, 0, 0))
        typing.type_of(node: dig(source.node, 0, 0))
        typing.type_of(node: dig(source.node, 0))

        typing.type_of(node: dig(source.node, 1, 0, 0))
        typing.type_of(node: dig(source.node, 1, 0))
        typing.type_of(node: dig(source.node, 1))
      end
    end
  end

  def test_const_class_module
    with_checker(<<RBS) do |checker|
class Nested
  class Class
  end

  class Class2
  end

  module Module
  end
end
RBS
      source = parse_ruby(<<-RUBY)
class ::Nested::Class < Nested::Class2
end

module Nested::Module
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        dig(source.node, 0).tap do |klass|
          typing.type_of(node: dig(klass, 0, 0, 0))
          typing.type_of(node: dig(klass, 0, 0))
          typing.type_of(node: dig(klass, 0))

          typing.type_of(node: dig(klass, 1, 0))
          typing.type_of(node: dig(klass, 1))
        end

        dig(source.node, 1).tap do |mod|
          typing.type_of(node: dig(mod, 0, 0))
          typing.type_of(node: dig(mod, 0))
        end
      end
    end
  end

  def test_block_without_hint
    with_checker(<<-RBS) do |checker|
class BlockWithoutHint
  def test: (Integer) -> void
          | (String) -> void
end
    RBS

      source = parse_ruby(<<-RUBY)
BlockWithoutHint.new.test(true) do
  # @type block: String
  3
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_typing_error(typing, size: 2) do |errors|
          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::UnresolvedOverloading, error
          end

          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::BlockBodyTypeMismatch, error
            assert_equal parse_type("::String"), error.expected
            assert_equal parse_type("::Integer"), error.actual
          end
        end
      end
    end
  end

  def test_bool_typing
    with_checker() do |checker|
      source = parse_ruby(<<-RUBY)
# @type var x: bool
x = true
x = false
x = 1
x = nil
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_typing_error(typing, size: 2) do |errors|
          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::IncompatibleAssignment, error
            assert_equal dig(source.node, 2), error.node
          end

          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::IncompatibleAssignment, error
            assert_equal dig(source.node, 3), error.node
          end
        end
      end
    end
  end

  def test_typing_record
    with_checker() do |checker|
      source = parse_ruby(<<-RUBY)
# @type var a: { foo: String, bar: Integer?, baz: Symbol? }
a = { foo: "hello", bar: 42, baz: _ = nil }

x = a[:foo]
y = a[:bar]
z = a[:baz]
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        _, _, context = construction.synthesize(source.node)

        assert_no_error typing

        assert_equal parse_type("::String"), context.type_env[:x]
        assert_equal parse_type("::Integer?"), context.type_env[:y]
        assert_equal parse_type("::Symbol?"), context.type_env[:z]
      end
    end
  end

  def test_typing_record_union
    with_checker() do |checker|
      source = parse_ruby(<<-RUBY)
# @type var x: { foo: String, bar: Integer } | String
x = { foo: "hello", bar: 42 }
x = "foo"
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        _, _, context = construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_typing_record_union_alias
    with_checker(<<RBS) do |checker|
type foo_bar = { foo: String, bar: Integer } | String
RBS
      source = parse_ruby(<<-RUBY)
# @type var x: foo_bar
x = { foo: "hello", bar: 42 }
x = "foo"
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        _, _, context = construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_typing_record_map1
    with_checker() do |checker|
      source = parse_ruby(<<-RUBY)
x = [1].map do |x|
  # @type block: { foo: String, bar: Integer }
  { foo: "hello", bar: x }
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        _, _, context = construction.synthesize(source.node)

        assert_no_error typing

        assert_equal parse_type("::Array[{ foo: ::String, bar: ::Integer }]"), context.type_env[:x]
      end
    end
  end

  def test_typing_record_nilable_attribute
    with_checker() do |checker|
      source = parse_ruby(<<-RUBY)
# @type var x: { foo: Integer? }
x = { }
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        _, _, context = construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_type_case_case_when_assignment
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type var x: String | Integer
x = (_ = nil)

case x
when String
  a = "String"
when Integer
  a = "Integer"
end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        _, _, context = construction.synthesize(source.node)

        assert_no_error typing
        assert_equal parse_type("::String"), context.type_env[:a]
      end
    end
  end

  def test_type_case_case_selector
    with_checker() do |checker|
      source = parse_ruby(<<RUBY)
x = ["foo", 2, :baz]

a = case y = z = x[0]
    when String
      y + ""
      z + ""
      "String"
    when Integer
      y + 0
      z + 0
      "Integer"
    when Symbol
      "Array[String]"
    end
RUBY

      with_standard_construction(checker, source) do |construction, typing|
        _, _, context = construction.synthesize(source.node)

        assert_no_error typing
        assert_equal parse_type("::String"), context.type_env[:a]
      end
    end
  end

  def test_type_if_else_when_assignment
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type var x: String | Integer
x = (_ = nil)

if x.is_a?(String)
  a = "String"
else
  a = "Integer"
end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        _, _, context = construction.synthesize(source.node)

        assert_no_error typing
        assert_equal parse_type("::String"), context.type_env[:a]
      end
    end
  end

  def test_bool_and_or
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type var x: bool

x = 30.is_a?(Integer) && true
x = 30.is_a?(String) || false
EOF

      with_standard_construction(checker, source) do |construction, typing|
        _, _, context = construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_and_is_a
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type var x: String | Float
# @type var y: Symbol | Integer

x = _ = nil
y = _ = nil

if x.is_a?(String) && y.is_a?(Integer)
  x + ""
  y + 3
else
  a = x
  b = y
end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        _, _, context = construction.synthesize(source.node)

        assert_no_error typing

        assert_equal parse_type("::String | ::Float | nil"), context.type_env[:a]
        assert_equal parse_type("::Symbol | ::Integer | nil"), context.type_env[:b]
      end
    end
  end

  def test_and_nested
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type var x: String | Float
# @type var y: String?
x = _ = ""
y = _ = nil

x.is_a?(String) && y && x + y
EOF

      with_standard_construction(checker, source) do |construction, typing|
        _, _, context = construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_or_nested
    with_checker do |checker|
      source = parse_ruby(<<RUBY)
# @type var x: String | Float
# @type var y: Integer?
# @type var z: String?
x = ""
y = 3

x.is_a?(Float) || (z = x)
y || (z = y)
x.is_a?(Float) || y || (z = x; z = y)
RUBY

      with_standard_construction(checker, source) do |construction, typing|
        _, _, context = construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_or_is_a
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type var x: String | Float
# @type var y: Symbol | Integer

x = _ = nil
y = _ = nil

if x.is_a?(Float) || y.is_a?(Symbol)
  a = x
  b = y
else
  x + ""
  y + 3
end
EOF

      with_standard_construction(checker, source) do |construction, typing|
        _, _, context = construction.synthesize(source.node)

        assert_no_error typing

        assert_equal parse_type("::String | ::Float | nil"), context.type_env[:a]
        assert_equal parse_type("::Symbol | ::Integer | nil"), context.type_env[:b]
      end
    end
  end

  def test_logic_or2
    with_checker do |checker|
      source = parse_ruby(<<RUBY)
x = [""].first
y = [""].first

return if x.nil? || y.nil?

x + y
RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_self_attributes
    with_checker(<<RBS) do |checker|
class Book
  attr_reader self.all: Array[Book]
end
RBS
      source = parse_ruby(<<RUBY)
Book.all.each do |book|
end
RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_proc_with_block_hint
    with_checker() do |checker|
      source = parse_ruby(<<RUBY)
# @type var f: ^(Integer) { (String) -> void } -> Array[String]
f = -> (n, &b) do
  b["foo"]
  ["bar"]
end
RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_proc_with_block_annotation
    with_checker() do |checker|
      source = parse_ruby(<<RUBY)
-> (n, &b) do
  # @type var n: Integer
  # @type var b: nil | ^(Integer) -> String

  if b
    b[n]
  end
end
RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _, _, = construction.synthesize(source.node)

        assert_no_error typing
        assert_equal parse_type("^(::Integer) ?{ (::Integer) -> ::String } -> ::String?"), type
      end
    end
  end

  def test_next_with_next_type
    with_checker(<<RBS) do |checker|
class NextTest
  def foo: () { (String) -> Integer } -> void
end
RBS
      source = parse_ruby(<<RUBY)
NextTest.new.foo do |x|
  next 10
  next [1,2,3]
  next
end
RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_typing_error(typing, size: 2) do |errors|
          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::BreakTypeMismatch, error
            assert_equal parse_type("::Array[::Integer]"), error.actual
            assert_equal parse_type("::Integer"), error.expected
          end

          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::BreakTypeMismatch, error
            assert_equal parse_type("nil"), error.actual
            assert_equal parse_type("::Integer"), error.expected
          end
        end
      end
    end
  end

  def test_next_without_method_type
    with_checker() do |checker|
      source = parse_ruby(<<RUBY)
unknown_method do |x|
  next 10
  next
end
RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_typing_error(typing, size: 1) do |errors|
          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::NoMethod, error
          end
        end
      end
    end
  end

  def test_next_without_break_context
    with_checker() do |checker|
      source = parse_ruby(<<RUBY)
def hello_world
  next
end
RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_typing_error(typing, size: 2) do |errors|
          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::UnexpectedJump, error
          end
        end
      end
    end
  end

  def test_break_with_block
    with_checker(<<RBS) do |checker|
class NextTest
  def foo: () { (String) -> Integer } -> String
end
RBS
      source = parse_ruby(<<RUBY)
NextTest.new.foo do |x|
  break "20"
  break 30
  break
end
RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_typing_error(typing, size: 2) do |errors|
          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::BreakTypeMismatch, error
            assert_equal parse_type("::Integer"), error.actual
            assert_equal parse_type("::String"), error.expected
          end

          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::ImplicitBreakValueMismatch, error
            assert_equal parse_type("::String"), error.jump_type
          end
        end
      end
    end
  end

  def test_break_without_method_type
    with_checker() do |checker|
      source = parse_ruby(<<RUBY)
unknown_method do |x|
  break 10
  break
end
RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_typing_error(typing, size: 1) do |errors|
          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::NoMethod, error
          end
        end
      end
    end
  end

  def test_break_without_break_context
    with_checker() do |checker|
      source = parse_ruby(<<RUBY)
def hello_world
  break
end
RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_typing_error(typing, size: 2) do |errors|
          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::UnexpectedJump, error
          end
        end
      end
    end
  end

  def test_break_with_annotation
    with_checker(<<RBS) do |checker|
class NextTest
  def foo: () { (String) -> Integer } -> String
end
RBS
      source = parse_ruby(<<RUBY)
NextTest.new.foo do |x|
  # @type break: Symbol
  break :exit
end
RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _ = construction.synthesize(source.node)

        assert_no_error typing
        assert_equal parse_type("::String | ::Symbol"), type
      end
    end
  end

  def test_and_is_a_nested
    with_checker(<<RBS) do |checker|
class Object
  def ==: (untyped) -> bool
end

class TestObject
  def ==: (untyped) -> bool

  attr_reader foo: String
end
RBS
      source = parse_ruby(<<RUBY)
class TestObject
  # @dynamic foo

  def ==(other)
    other.is_a?(TestObject) &&
      other.foo == foo &&
      other.bar == bar
  end
end
RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _ = construction.synthesize(source.node)

        assert_typing_error typing, size: 2 do |errors|
          assert_all!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::NoMethod, error
            assert_equal :bar, error.method
          end
        end
      end
    end
  end

  def test_value_case
    with_checker(<<RBS) do |checker|
type allowed_key = :foo | :bar | nil | Integer
RBS
      source = parse_ruby(<<RUBY)
# @type var x: allowed_key
x = _ = nil

# @type var y: nil
# @type var z: Symbol

case x
when nil
  y = x
when :foo
  z = x
when Symbol
  z = x
when Integer
  x + 1
end
RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _ = construction.synthesize(source.node)
        assert_no_error typing
      end
    end
  end

  def test_value_case2
    with_checker(<<RBS) do |checker|
type allowed_key = :foo | :bar
RBS
      source = parse_ruby(<<RUBY)
# @type var x: allowed_key
x = _ = nil

# @type var a: bool

a = case x
    when :foo
      true
    when :bar
      false
    end
RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _ = construction.synthesize(source.node)
        assert_no_error typing
      end
    end
  end

  def test_value_case3
    with_checker(<<RBS) do |checker|
type allowed_key = Integer | String
RBS
      source = parse_ruby(<<RUBY)
# @type var x: allowed_key
x = _ = nil

# @type var a: bool

a = case x
    when 1
      (x + 1).zero?
    when "2"
      (x + "").size.zero?
    when Integer, String
      false
    end
RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _ = construction.synthesize(source.node)
        assert_no_error typing
      end
    end
  end

  def test_case_when_var
    with_checker() do |checker|
      source = parse_ruby(<<RUBY)
# @type var x: Integer?
x = _ = nil

case
when x
  x + 1
end
RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _ = construction.synthesize(source.node)
        assert_no_error typing
      end
    end
  end

  def test_defs_self
    with_checker() do |checker|
      source = parse_ruby(<<'RUBY')
class C < UnknownSuperClass
  def self.foo
  end
end
RUBY

      with_standard_construction(checker, source) do |construction, typing|
        _type, _ = construction.synthesize(source.node)

        assert_typing_error(typing) do |errors|
          assert_count(errors, 2) do |error|
            error.instance_of? Diagnostic::Ruby::UnknownConstant
          end
        end
      end
    end
  end

  def test_case_when_arg
    with_checker() do |checker|
      source = parse_ruby(<<'RUBY')
class C
  def self.foo(x)
    case x
    when Integer
      x + 1
    when String
      x + ""
    end
  end
end
RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_typing_error(typing, size: 2) do |errors|
          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::UnknownConstant, error
            assert_equal :C, error.name
          end
        end
      end
    end
  end

  def test_if_is_a_assign
    with_checker(<<RBS) do |checker|
interface _Hello
  def to_s: () -> String
end
RBS
      source = parse_ruby(<<'RUBY')
# @type var x: _Hello
x = ""

if (_ = x).is_a?(String)
  x + ""
end
RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)
        assert_no_error typing
      end
    end
  end

  def test_rescue_rbs_errors
    with_checker(<<RBS) do |checker|
interface _Hello
  def to_s: () -> String
  def to_s: () -> String
end
RBS
      source = parse_ruby(<<'RUBY')
# @type var x: _Hello
x = ""

x.to_s()
RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)
        assert_typing_error(typing) do |error|
          assert_instance_of Diagnostic::Ruby::UnexpectedError, error
        end
      end
    end
  end

  def test_inference
    with_checker <<-EOF do |checker|
class Inference
  def foo: [A] (A, A) -> A
end
    EOF

      source = parse_ruby(<<-'EOF')
Inference.new.foo(1, "")
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        type, _ = construction.synthesize(source.node)

        assert_no_error typing

        assert_equal parse_type("::Integer | ::String"), type
      end
    end
  end

  def test_issue_269_1
    # https://github.com/soutaro/steep/issues/269
    with_checker <<-EOF do |checker|
class Test269
  def foo: (untyped) -> void
end
    EOF

      source = parse_ruby(<<-'RUBY')
class Test269
  def foo(x)
    x.bar() {|(a, (b, c))|
      a.hello()
    }
  end
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _ = construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_issue_269_2
    # https://github.com/soutaro/steep/issues/269
    with_checker <<-EOF do |checker|
class Test269
  def foo: (Integer) -> void
end
    EOF

      source = parse_ruby(<<-'RUBY')
class Test269
  def foo(x)
    x.bar() {|(key, value)| }
  end
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _ = construction.synthesize(source.node)

        assert_typing_error(typing, size: 1) do |errors|
          assert_any!(errors) do | error|
            assert_instance_of Diagnostic::Ruby::NoMethod, error
          end
        end
      end
    end
  end

  def test_block_implements
    with_checker <<-EOF do |checker|
class String
  def extra_method: (String) -> String

  def self.class_eval: () { () -> void } -> void
end

class TestImplements
end
    EOF

      source = parse_ruby(<<-'RUBY')
class TestImplements
  String.class_eval do
    # @implements String

    def extra_method(x)
      self + x
    end
  end
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _ = construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_block_implements_singleton
    with_checker <<-EOF do |checker|
class Object
  def self.class_eval: () { () -> void } -> void
end

class TestInside
  def initialize: (String) -> void
  def self.foo: () -> void
  def self.make_copy: () -> TestInside
end

class TestOutside
end
    EOF

      source = parse_ruby(<<-'RUBY')
class TestOutside
  TestInside.class_eval do
    # @implements TestInside

    foo()

    def self.make_copy
      TestInside.new("Foo")
    end
  end
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _ = construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_nil_block
    with_checker <<-EOF do |checker|
class TestNilBlock
  def foo: () { () -> void } -> void
  def bar: () -> void
end
    EOF

      source = parse_ruby(<<-'RUBY')
TestNilBlock.new.foo(&nil)
TestNilBlock.new.bar(&nil)
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _ = construction.synthesize(source.node)

        assert_typing_error typing, size: 1 do |errors|
          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::RequiredBlockMissing, error
            assert_equal "foo", error.location.source
          end
        end
      end
    end
  end

  def test_issue_332
    with_checker <<-EOF do |checker|
module Issue332
  class Foo
    def test: (Integer) -> void
            | (String) -> void
  end

  class Bar < Foo
  end
end
    EOF

      source = parse_ruby(<<-'RUBY')
module Issue332
  class Bar
    def test(x)
      super(x)
    end
  end
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _ = construction.synthesize(source.node)

        assert_typing_error(typing, size: 1) do |errors|
          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::UnresolvedOverloading, error
            assert_equal parse_type("::Issue332::Bar"), error.receiver_type
            assert_equal :test, error.method_name
            assert_equal(
              [
                parse_method_type("(::Integer) -> void"),
                parse_method_type("(::String) -> void")
              ],
              error.method_types
            )
          end
        end
      end
    end
  end

  def test_issue_328
    with_checker <<-EOF do |checker|
module Issue328
  class Foo
    def to_h: [A, B] () { () -> [A, B] } -> Hash[A, B]
  end
end
    EOF

      source = parse_ruby(<<-'RUBY')
Issue328::Foo.new.to_h { [1, ""] }
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _ = construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_issue_293
    with_checker do |checker|
      source = parse_ruby(<<-'RUBY')
begin
  1+2
rescue
  retry
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _ = construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_issue_372
    with_checker(<<-RBS) do |checker|
class Issue372
  def f: () ?{ () -> void } -> void
  def g: () ?{ () -> void } -> void
end
    RBS

      source = parse_ruby(<<-'RUBY')
class Issue372
  def f(&block)
  end

  def g(&block)
    f(&block)
  end
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _ = construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_ruby3_endless_def
    with_checker(<<-RBS) do |checker|
module Ruby3
  class Test
    def foo: (String) -> Integer
  end
end
    RBS

      source = parse_ruby(<<-'RUBY')
module Ruby3
  class Test
    def foo(x) = x.size
  end
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _ = construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_ruby3_numbered_parameter1
    with_checker do |checker|
      source = parse_ruby(<<RUBY)
[1].map { _1.to_s }
RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _ = construction.synthesize(source.node)

        assert_equal parse_type("::Array[::String]"), type

        assert_no_error typing
      end
    end
  end

  def test_ruby3_numbered_parameter2
    with_checker(<<RBS) do |checker|
module Ruby3
  class Foo
    def foo: () { ([String, Integer]) -> void } -> void
  end
end
RBS

      source = parse_ruby(<<RUBY)
Ruby3::Foo.new().foo do
  _1[0] + ""
  _1[1] + 0
end
RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _ = construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_ruby3_numbered_parameter3
    with_checker(<<RBS) do |checker|
module Ruby3
  class Foo
    def foo: () { ([String, Integer]) -> void } -> void
  end
end
RBS

      source = parse_ruby(<<RUBY)
Ruby3::Foo.new().foo do
  _1 + ""
  _2 + 0
end
RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _ = construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_ruby3_numbered_parameter4
    with_checker(<<RBS) do |checker|
module Ruby3
  class Foo
    def foo: (Integer) { (Integer) -> void } -> void

    def bar: (foo: Integer) { (Integer) -> void } -> void
  end
end
RBS

      source = parse_ruby(<<RUBY)
Ruby3::Foo.new().foo { _1 }
Ruby3::Foo.new().bar { _1 }
RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _ = construction.synthesize(source.node)

        assert_typing_error(typing, size: 2) do |errors|
          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::InsufficientPositionalArguments, error
            assert_equal "foo", error.location.source
          end

          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::InsufficientKeywordArguments, error
            assert_equal "bar", error.location.source
          end
        end
      end
    end
  end

  def test_type_check_def_without_decl
    with_checker(<<RBS) do |checker|
RBS

      source = parse_ruby(<<RUBY)
def HelloWorld(x, y = 1, *z, a:, b: false, **c, &block)
  x
  y
  z
  a
  b
  c
  block
end
RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _ = construction.synthesize(source.node)
        assert_typing_error(typing, size: 1) do |errors|
          assert_all!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::UndeclaredMethodDefinition, error
          end
        end
      end
    end
  end

  def test_break_without_value_to_block
    with_checker(<<RBS) do |checker|
class NextTest
  def foo: () { (String) -> Integer } -> String
end
RBS
      source = parse_ruby(<<RUBY)
NextTest.new.foo do |x|
  break
end
RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_typing_error(typing, size: 1) do |errors|
          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::ImplicitBreakValueMismatch, error
            assert_equal parse_type("::String"), error.jump_type
          end
        end
      end
    end
  end

  def test_issue_389
    with_checker(<<RBS) do |checker|
class Object
  def x1: () { (untyped) -> untyped } -> void
  def x2: () { (untyped) -> void } -> void
  def x3: () { (untyped) -> Symbol } -> void
end
RBS
      source = parse_ruby(<<RUBY)
# @type var kind: :instance | :singleton
kind = :instance

tap do
  kind = :singleton
end

x1 { kind = :instance }
x2 { kind = :instance }
x3 { kind = :instance }
RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_break_from_loop
    with_checker(<<RBS) do |checker|
class Object
  def loop: () { () -> void } -> bot
end
RBS
      source = parse_ruby(<<RUBY)
loop do
  break
end
RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_missing_args_with_csend
    with_checker(<<-RBS) do |checker|
 module MissingArgs
   class Foo
     def csend: (Integer) -> void

     def csendkw: (foo: Integer) -> void
   end
 end
    RBS

      source = parse_ruby(<<-'RUBY')
MissingArgs::Foo.new&.csend
MissingArgs::Foo.new&.csendkw
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _ = construction.synthesize(source.node)

        assert_typing_error(typing, size: 2) do |errors|
          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::InsufficientPositionalArguments, error
            assert_equal "csend", error.location.source
          end

          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::InsufficientKeywordArguments, error
            assert_equal "csendkw", error.location.source
          end
        end
      end
    end
  end

  def test_splat_arg_no_param
    with_checker(<<-RBS) do |checker|
class EachNoParam
  def each: () -> void
end
    RBS

      source = parse_ruby(<<-'RUBY')
a = [1,2,3]
EachNoParam.new.each(*a)
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _ = construction.synthesize(source.node)

        assert_typing_error(typing, size: 1) do |errors|
          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::UnexpectedPositionalArgument, error
          end
        end
      end
    end
  end

  def test_generic_alias_error
    with_checker(<<-RBS) do |checker|
type list[T] = nil
             | [ T, list[T] ]
    RBS

      source = parse_ruby(<<-'RUBY')
# @type var ints: list[Integer]
ints = ["1", ["2", nil]]
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _ = construction.synthesize(source.node)

        assert_typing_error(typing, size: 1) do
          assert_any!(typing.errors) do |error|
            assert_instance_of Diagnostic::Ruby::IncompatibleAssignment, error
          end
        end
      end
    end
  end

  def test_bounded_generics
    with_checker(<<-RBS) do |checker|
class Q[T < _Pushable]
  attr_reader queue: T

  def push: [S < _ToStr] (S) -> S
end

interface _Pushable
  def push: (String) -> void
end

interface _ToStr
  def to_str: () -> String
end
    RBS

      source = parse_ruby(<<-'RUBY')
class Q
  def push(obj)
    queue.push(obj.to_str)

    # @type var x: _ToStr
    x = obj

    obj
  end
end

# @type var q: Q[Array[String]]
q = Q.new()
q.push("") + ""
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_typing_error(typing, size: 1) do |errors|
          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::MethodDefinitionMissing, error
          end
        end
      end
    end
  end

  def test_bounded_generics_apply
    with_checker(<<-RBS) do |checker|
class Q[T < _Pushable]
  attr_reader queue: T

  def push: [S < _ToStr] (S) -> S
end

interface _Pushable
  def push: (String) -> void
end

interface _ToStr
  def to_str: () -> String
end
    RBS

      source = parse_ruby(<<-'RUBY')
# @type var q: Q[Array[String]]
q = Q.new()
q.push(1)
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _ = construction.synthesize(source.node)

        assert_equal parse_type("untyped"), type
        assert_typing_error(typing, size: 1) do |errors|
          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::ArgumentTypeMismatch, error
          end
        end
      end
    end
  end

  def test_generic_alias
    with_checker(<<-RBS) do |checker|
type list[out A] = [A, list[A]] | nil

class A
  def car: [X] (list[X]) -> X?

  def cdr: [X] (list[X]) -> list[X]?
end
    RBS

      source = parse_ruby(<<-'RUBY')
class A
  def car(list)
    if list
      list[0]
    end
  end

  def cdr(list)
    if list
      list[1]
    end
  end
end

# @type var a: list[Integer]
a = [1, [2, [3, nil]]]

car = A.new.car(a)
cdr = A.new.cdr(a)
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _, context = construction.synthesize(source.node)

        assert_no_error(typing)

        assert_equal parse_type("::Integer?"), context.type_env[:car]
        assert_equal parse_type("::list[::Integer]?"), context.type_env[:cdr]
      end
    end
  end

  def test_send_solution_block_body_type_check_failure
    with_checker(<<-RBS) do |checker|
class Solution[X]
  def foo: [A] () { () -> Integer } -> [X, A]
end
    RBS

      source = parse_ruby(<<-'RUBY')
class Solution
  def bar
    z = foo { "foo" }
    1+2
  end
end
      RUBY

      with_standard_construction(checker, source, cursor: [4, 5]) do |construction, typing|
        type, _ = construction.synthesize(source.node)

        assert_equal parse_type("[X, untyped]", variables: [:X]), typing.cursor_context.context.type_env[:z]
      end
    end
  end

  def test_send_solution_block_body_type_check_failure_with_annotation
    with_checker(<<-RBS) do |checker|
class Solution[X]
  def foo: [A, B] (B) { (B) -> Integer } -> [X, A]
end
    RBS

      source = parse_ruby(<<-'RUBY')
class Solution
  def bar
    z = foo(true) {|x|
      # @type var x: Integer
      "foo"
    }
    1+2
  end
end
      RUBY

      with_standard_construction(checker, source, cursor: [7, 5]) do |construction, typing|
        type, _ = construction.synthesize(source.node)

        assert_equal parse_type("[X, untyped]", variables: [:X]), typing.cursor_context.context.type_env[:z]
      end
    end
  end

  def test_send_solution_block_parameter_unsupported
    with_checker(<<-RBS) do |checker|
class Solution[X]
  def foo: [A] () { () -> Integer } -> [X, A]
end
    RBS

      source = parse_ruby(<<-'RUBY')
class Solution
  def bar
    z = foo() {|(a, (b, c))| "foo" }
    1+2
  end
end
      RUBY

      with_standard_construction(checker, source, cursor: [4, 5]) do |construction, typing|
        type, _ = construction.synthesize(source.node)

        assert_equal parse_type("[X, untyped]", variables: [:X]), typing.cursor_context.context.type_env[:z]
      end
    end
  end

  def test_send_solution_block_pass
    with_checker(<<-RBS) do |checker|
class Solution[X]
  def foo: [A] () { () -> A } -> [X, A]
end
    RBS

      source = parse_ruby(<<-'RUBY')
block = -> { "foo" }
Solution.new.foo(&block)
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _ = construction.synthesize(source.node)
        assert_equal parse_type("[untyped, ::String]", variables: [:X]), type
      end
    end
  end

  def test_send_solution_block_pass_nil
    with_checker(<<-RBS) do |checker|
class Solution[X]
  def foo: [A] (^(A) -> A) { () -> void } -> [X, A]
end
    RBS

      source = parse_ruby(<<-'RUBY')
block = -> (x) do
  # @type var x: Integer
  ""
end
Solution.new.foo(block, &nil)
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _ = construction.synthesize(source.node)
        assert_equal parse_type("[untyped, untyped]", variables: [:X]), type

        assert_typing_error(typing, size: 2) do |errors|
          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::RequiredBlockMissing, error
          end

          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::UnsatisfiableConstraint, error
          end
        end
      end
    end
  end

  def test_send_solution_block_pass_error
    with_checker(<<-RBS) do |checker|
class Solution[X]
  def foo: [A] () { (A) -> A } -> [X, A]
end
    RBS

      source = parse_ruby(<<-'RUBY')
block = -> (x) do
  # @type var x: Integer
  "foo"
end
Solution.new.foo(10, &block)
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _ = construction.synthesize(source.node)
        assert_equal parse_type("[untyped, untyped]", variables: [:X]), type
      end
    end
  end

  def test_send_solution_required_block_is_missing
    with_checker(<<-RBS) do |checker|
class Solution[X]
  def foo: [A] (^(A) -> A) { () -> void } -> [X, A]
end
    RBS

      source = parse_ruby(<<-'RUBY')
block = -> (x) do
  # @type var x: Integer
  "foo"
end
Solution.new.foo(block)
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _ = construction.synthesize(source.node)
        assert_equal parse_type("[untyped, untyped]", variables: [:X]), type
      end
    end
  end

  def test_send_solution_unexpected_block_is_given
    with_checker(<<-RBS) do |checker|
class Solution[X]
  def foo: [A] (^(A) -> A) -> [X, A]
end
    RBS

      source = parse_ruby(<<-'RUBY')
block = -> (x) do
  # @type var x: Integer
  "foo"
end
Solution.new.foo(block, &block)
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _ = construction.synthesize(source.node)
        assert_equal parse_type("[untyped, untyped]", variables: [:X]), type
      end
    end
  end

  def test_return_no_value
    with_checker(<<-RBS) do |checker|
class ReturnNoValue
  def foo: () -> Integer

  def bar: () -> String?
end
    RBS

      source = parse_ruby(<<-'RUBY')
class ReturnNoValue
  def foo
    return
  end

  def bar
    return
  end
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_typing_error(typing, size: 1) do
          assert_any!(typing.errors) do |error|
            assert_instance_of Diagnostic::Ruby::ReturnTypeMismatch, error
            assert_equal "The method cannot return a value of type `nil` because declared as type `::Integer`", error.header_line
          end
        end
      end
    end
  end

  def test_context_typing_bool
    with_checker(<<-RBS) do |checker|
    RBS

      source = parse_ruby(<<-'RUBY')
flag = false

while flag
  flag = false
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _, _ = construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_proc_type_case
    with_checker(<<-RBS) do |checker|
class ProcTypeCase
  def foo: (String | ^() -> String) -> String
end
    RBS

      source = parse_ruby(<<-'RUBY')
class ProcTypeCase
  def foo(callback)
    if callback.is_a?(Proc)
      callback = callback[]
    end

    callback
  end
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _, _ = construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_lambda_with_block
    with_checker(<<-RBS) do |checker|
class LambdaWithBlock
  def foo: () { (String) -> void } -> void
end
    RBS

      source = parse_ruby(<<-'RUBY')
class LambdaWithBlock
  def foo(&block)
    # @type var foo: ^() { (Integer) -> void } -> void
    foo = -> (&block) do
      block[123]
    end
  end
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _, _ = construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_lambda_with_block_alias
    with_checker(<<-RBS) do |checker|
type callback[T] = ^() { (T) -> void } -> T
    RBS

      source = parse_ruby(<<-'RUBY')
# @type var foo: callback[Integer]
foo = -> (&block) { block[80]; 123 }
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _, _ = construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_lambda_with_block_non_proc
    with_checker(<<-RBS) do |checker|
    RBS

      source = parse_ruby(<<-'RUBY')
# @type var foo: Integer
foo = -> (&block) do
  block
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _, _ = construction.synthesize(source.node)

        assert_typing_error(typing, size: 2) do |errors|
          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::IncompatibleAssignment, error
          end
        end
      end
    end
  end

  def test_lambda_with_block_non_proc_arg
    with_checker(<<-RBS) do |checker|
    RBS

      source = parse_ruby(<<-'RUBY')
foo = -> (&block) do
  # @type var block: Integer
  block+1
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _, _ = construction.synthesize(source.node)

        assert_equal parse_type("^() { () -> untyped } -> ::Integer"), type

        assert_typing_error(typing, size: 1) do |errors|
          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::ProcTypeExpected, error
            assert_equal parse_type("::Integer"), error.type
          end
        end
      end
    end
  end

  def test_flat_map
    with_checker(<<-RBS) do |checker|
class FlatMap
  def flat_map: [A] () { (String) -> (A | Array[A]) } -> Array[A]
end
    RBS

      source = parse_ruby(<<-'RUBY')
# @type var a: FlatMap
a = _ = nil
a.flat_map {|s| [s] }
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _, _ = construction.synthesize(source.node)

        assert_no_error typing
        assert_equal parse_type("::Array[::String]"), type
      end
    end
  end

  def test_filter_map
    with_checker(<<-RBS) do |checker|
class FilterMap
  def filter_map: [A] () { (String) -> (A | nil | false) } -> Array[A]
end
    RBS

      source = parse_ruby(<<-'RUBY')
# @type var a: FilterMap
a = _ = nil
a.filter_map do |s|
  if _ = s
    s.size
  end
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _, _ = construction.synthesize(source.node)

        assert_no_error typing
        assert_equal parse_type("::Array[::Integer]"), type
      end
    end
  end

  def test_filter_map_compact
    with_checker(<<-RBS) do |checker|
class Array[unchecked out Element]
  def filter_map: [A] () { (Element) -> (A | nil | false) } -> Array[A]
end
    RBS

      source = parse_ruby(<<-'RUBY')
a = ["1", nil]
a.filter_map(&:itself)
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _, _ = construction.synthesize(source.node)

        assert_no_error typing
        assert_equal parse_type("::Array[::String]"), type
      end
    end
  end

  def test_array_compact
    with_checker(<<-RBS) do |checker|
class Array[unchecked out Element]
  def compact: () -> Array[Element]
end

class Array2 < Array[String?]
end
    RBS

      source = parse_ruby(<<-'RUBY')
# @type var result: Array[String]
result = _ = nil

a = ["1", nil]
result = a.compact

# @type var b: Array2
b = _ = nil
result = b.compact
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _, _ = construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_hash_compact
    with_checker(<<-RBS) do |checker|
class Hash[unchecked out K, unchecked out V]
  def compact: () -> Hash[K, V]
end

class Hash2 < Hash[Symbol, String?]
end
    RBS

      source = parse_ruby(<<-'RUBY')
# @type var result: Hash[Symbol, String]
result = _ = nil

a = {foo: "1", bar: nil}
result = a.compact

# @type var b: Hash2
b = _ = nil
result = b.compact
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _, _ = construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_to_proc_syntax_optional_arg
    with_checker(<<-RBS) do |checker|
class OptionalArgMethod
  def foo: (?untyped, *untyped, ?a: untyped, **untyped) -> String
         | () -> Integer
end
    RBS

      source = parse_ruby(<<-'RUBY')
[OptionalArgMethod.new].map(&:foo)
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _, _ = construction.synthesize(source.node)

        assert_no_error typing
        assert_equal parse_type("::Array[::String]"), type
      end
    end
  end

  def test_splat_in_array
    with_checker(<<-RBS) do |checker|
class Range[T]
  def to_a: () -> Array[T]
end
    RBS

      source = parse_ruby(<<-'RUBY')
a = [*'0'..'9']
b = [*123]

# @type var x: [Integer, String]
x = [1, "a"]
c = [*x]
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        _, constr = construction.synthesize(source.node)

        assert_no_error typing
        assert_equal parse_type("::Array[::String]"), constr.context.type_env[:a]
        assert_equal parse_type("::Array[::Integer]"), constr.context.type_env[:b]
        assert_equal parse_type("::Array[::Integer | ::String]"), constr.context.type_env[:c]
      end
    end
  end

  def test_to_a_untyped
    with_checker(<<-RBS) do |checker|
    RBS

      source = parse_ruby(<<-'RUBY')
# @type var a: untyped
a = _ = nil
[*a]

# @type var b: top
b = _ = nil
[*b]

# @type var c: bot
c = _ = nil
[*c]
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        _, constr = construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_case_const_unexpected_error
    with_checker(<<-RBS) do |checker|
class UnexpectedErrorTest
  def foo: () -> void
end
      RBS

      source = parse_ruby(<<-'RUBY')
class UnexpectedErrorTest
  def foo
    field = _ = 123
    case field.label
    when Object::FOO
    end
  end
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_typing_error(typing, size: 1) do |errors|
          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::UnknownConstant, error
          end
        end
      end
    end
  end

  def test_const_one_error
    with_checker(<<-RBS) do |checker|
    RBS

      source = parse_ruby(<<-'RUBY')
X::Y::Z
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_typing_error(typing, size: 1) do |errors|
          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::UnknownConstant, error
            assert_equal :X, error.name
          end
        end
      end
    end
  end

  def test_flow_sensitive_not
    with_checker(<<-RBS) do |checker|
class String
  def empty?: () -> bool
end

class NilClass
  def !: () -> true
end
    RBS

      source = parse_ruby(<<-'RUBY')
doc = (_ = 1) ? "" : nil
doc = ((_ = 2) ? "" : nil) if !doc || doc.empty?
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_no_error(typing)
      end
    end
  end

  def test_super_class_not_const
    with_checker(<<-RBS) do |checker|
module SuperClassNotConst
  class Foo
  end
end
    RBS

      source = parse_ruby(<<-'RUBY')
module SuperClassNotConst
  class Foo < Class.new
  end
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_no_error(typing)
      end
    end
  end

  def test_keyword_param_methods
    with_checker(<<-RBS) do |checker|
module KeywordParamMethod
  class Foo
    def bar: (*String, name: Symbol) -> void
  end
end
    RBS

      source = parse_ruby(<<-'RUBY')
module KeywordParamMethod
  class Foo
    def bar(*args, name:)
    end
  end
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_no_error(typing)
      end
    end
  end

  def test_ruby31_shorthand_hash
    with_checker do |checker|
      source = parse_ruby(<<RUBY)
x = 1
{ x: }
RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _ = construction.synthesize(source.node)

        assert_equal parse_type("::Hash[::Symbol, ::Integer]"), type

        assert_no_error typing
      end
    end
  end

  def test_module_annotation_merge_error
    with_checker do |checker|
      source = parse_ruby(<<RUBY)
module Mod

  ->(){}

end
RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _ = construction.synthesize(source.node)

        assert_typing_error(typing, size: 1) do |errors|
          errors[0].tap do |error|
            assert_instance_of Diagnostic::Ruby::UnknownConstant, error
          end
        end
      end
    end
  end

  def test_anonymouse_block_forwarding
    with_checker(<<RBS) do |checker|
class AnonBlockForwarding
  def foo: () { (String) -> void } -> void
end
RBS
      source = parse_ruby(<<RUBY)
class AnonBlockForwarding
  def foo(&)
    ["a", "b"].each(&)
  end
end
RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _ = construction.synthesize(source.node)

        assert_no_error(typing)
      end
    end
  end

  def test_optional_parameter_value_with_wrong_type
    with_checker(<<RBS) do |checker|
class OptionalParamValues
  def foo: (?String, ?foo: String) -> void
end
RBS
      source = parse_ruby(<<RUBY)
class OptionalParamValues
  def foo(x = 123, foo: true)
  end
end
RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _ = construction.synthesize(source.node)

        assert_typing_error(typing, size: 2) do |errors|
          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::IncompatibleAssignment, error
            assert_equal "Cannot assign a value of type `::Integer` to an expression of type `::String`", error.header_line
          end
        end

        assert_typing_error(typing, size: 2) do |errors|
          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::IncompatibleAssignment, error
            assert_equal "Cannot assign a value of type `bool` to an expression of type `::String`", error.header_line
          end
        end
      end
    end
  end

  def test_const_inline_annotation
    with_checker(<<RBS) do |checker|
module A
  def foo: () -> void
end
RBS
      source = parse_ruby(<<RUBY)
module A
  # @type const X: String

  def foo
    X + ""
  end
end
RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _ = construction.synthesize(source.node)

        assert_no_error(typing)
      end
    end
  end

  def test_issue_583
    with_checker <<-EOF do |checker|
module Issue583
  class TestArray[unchecked out Elem] < Object
    def to_h: () -> Hash[untyped, untyped]
      | [T, S] () { (Elem) -> [ T, S ] } -> Hash[T, S]
  end

  class TestClass
    def register_block: (TestArray[::String]) { (String) -> void } -> ::Hash[::String, ^(String) -> void]
  end
end
    EOF

      source = parse_ruby(<<-'RUBY')
module Issue583
  class TestClass
    def register_block(field_names, &block)
      field_names.to_h do |field_name|
        [field_name, block]
      end
    end
  end
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _ = construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_method_purity_attribute
    with_checker(<<RBS) do |checker|
class HelloPure
  attr_reader email: String?
end
RBS
      source = parse_ruby(<<RUBY)
hello = HelloPure.new

if hello.email
  hello.email + ""
end
RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _ = construction.synthesize(source.node)

        assert_no_error(typing)
      end
    end
  end

  def test_method_purity_attribute2
    with_checker(<<RBS) do |checker|
class HelloPure
  attr_accessor email: String?
end
RBS
      source = parse_ruby(<<RUBY)
hello = HelloPure.new

if hello.email
  hello.email = nil
  hello.email + ""
end
RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _, context = construction.synthesize(source.node)

        assert_typing_error(typing, size: 1) do |errors|
          errors[0].tap do |error|
            assert_instance_of Diagnostic::Ruby::NoMethod, error
            assert_equal :+, error.method
          end
        end
      end
    end
  end

  def test_method_flow_sensitive_is_a
    with_checker(<<RBS) do |checker|
class TestClass
  attr_accessor value: String | Integer
end
RBS
      source = parse_ruby(<<RUBY)
object = TestClass.new

if object.value.is_a?(String)
  object.value + ""
end
RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _, context = construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_method_flow_sensitive_nilp
    with_checker(<<RBS) do |checker|
class TestClass
  attr_accessor value: String?
end
RBS
      source = parse_ruby(<<RUBY)
object = TestClass.new

unless object.value.nil?
  object.value + ""
end
RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _, context = construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_method_flow_sensitive_arg_is_receiver
    with_checker(<<RBS) do |checker|
class TestClass
  attr_accessor value: String?
end
RBS
      source = parse_ruby(<<RUBY)
object = TestClass.new

case x = object.value
when String
  object.value + ""
end
RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _, context = construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_method_flow_sensitive_arg_equals_receiver
    with_checker(<<RBS) do |checker|
class TestClass
  attr_accessor value: String?
end
RBS
      source = parse_ruby(<<RUBY)
object = TestClass.new

case x = object.value
when "hello"
  object.value + ""
end
RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _, context = construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_method_flow_sensitive_not
    with_checker(<<RBS) do |checker|
class TestClass
  attr_accessor value: String?
end
RBS
      source = parse_ruby(<<RUBY)
object = TestClass.new

unless !object.value
  object.value + ""
end
RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _, context = construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_method_flow_sensitive_array_aref
    with_checker(<<RBS) do |checker|
RBS
      source = parse_ruby(<<RUBY)
array = [1, nil]

if array[0]
  array[0] + 1
end
RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _, context = construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_method_flow_sensitive_hash_aref
    with_checker(<<RBS) do |checker|
RBS
      source = parse_ruby(<<RUBY)
hash = { name: "hoge", email: nil }

if hash[:name]
  hash[:name] + ""
end
RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _, context = construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_method_type_refinements_if
    with_checker(<<-RBS) do |checker|
class RefinementIf
  attr_reader value: String
end
      RBS
      source = parse_ruby(<<RUBY)
ref = RefinementIf.new

if _ = 123
  ref.value + ""
end
ref.value + ""
RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _, context = construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_assignment_in_block
    with_checker(<<-RBS) do |checker|
      RBS
      source = parse_ruby(<<RUBY)
# @type var a: String?
a = nil

tap do |x|
  a = ""
end

if a
  a + ""
end
RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _, context = construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_issue_595_generics_type_inference
    with_checker(<<-RBS) do |checker|
class ConfigurationReader
  def read: [T](T, ^() -> T) -> T
end
      RBS
      source = parse_ruby(<<-RUBY)
reader = ConfigurationReader.new
reader.read("123", -> () { 123 })
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _, context = construction.synthesize(source.node)

        assert_no_error typing
        assert_equal parse_type("::Integer | ::String"), type
      end
    end
  end

  def test_issue_610_type_param_block_param
    with_checker(<<-RBS) do |checker|
module Issue610
  class Foo
    def ok: [T] (T) { () -> ^(::Integer) -> T } -> T
    def ng: [T] (T) { () -> ^(T) -> T } -> T
  end
end
      RBS
      source = parse_ruby(<<-RUBY)
ok = Issue610::Foo.new.ok(123) do -> (x) { x + 1 } end
ng = Issue610::Foo.new.ng(123) do -> (x) { x + 1 } end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _, context = construction.synthesize(source.node)

        assert_equal parse_type("::Integer"), context.type_env[:ok]
        assert_equal parse_type("::Integer"), context.type_env[:ng]
      end
    end
  end

  def test_issue_610_type_param_block_param_generic_constraint
    with_checker(<<-RBS) do |checker|
module Issue610
  class Foo
    def ng: [T < Integer] (T) { () -> ^(T) -> T } -> T
  end
end
      RBS
      source = parse_ruby(<<-RUBY)
ng = Issue610::Foo.new.ng(123) do -> (x) { x + 1 } end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _, context = construction.synthesize(source.node)

        assert_no_error typing

        assert_equal parse_type("::Integer"), context.type_env[:ng]
      end
    end
  end

  def test_lvar_special
    with_checker(<<-RBS) do |checker|
      RBS
      source = parse_ruby(<<-RUBY)
_ = 123
_ + 1

__skip__ = 123
__skip__ + 123

__any__ = :foo
__any__ + 123

_, __any__ = [123, :foo]

[1,2,3].each do |_|
  [2].each do
  end
end

-> (_) { 123 }
RUBY
      with_standard_construction(checker, source) do |construction, typing|
        type, _, context = construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_type_narrowing_assignment
    with_checker(<<-RBS) do |checker|
class NarrowingAssignmentTest
  def foo: () -> (Integer | String)
end
      RBS
      source = parse_ruby(<<-RUBY)
case value = NarrowingAssignmentTest.new.foo()
when Integer
  "hello"
when String
  value
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _, context = construction.synthesize(source.node)

        assert_no_error typing

        assert_equal parse_type("::String"), type
      end
    end
  end

  def test_type_if_union_unify
    with_checker(<<-RBS) do |checker|
      RBS
      source = parse_ruby(<<-RUBY)
if _ = 123
  Object.new
else
  String.new
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _, context = construction.synthesize(source.node)

        assert_no_error typing

        assert_equal parse_type("::Object"), type
      end
    end
  end

  def test_type_case_union_unify
    with_checker(<<-RBS) do |checker|
      RBS
      source = parse_ruby(<<-RUBY)
case _ = 123
when String
  Object.new
else
  String.new
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _, context = construction.synthesize(source.node)

        assert_no_error typing

        assert_equal parse_type("::Object"), type
      end
    end
  end

  def test_masgn_union_tuple
    with_checker(<<-RBS) do |checker|
      RBS
      source = parse_ruby(<<-RUBY)
x, y =
  if _ = 123
    ["String", 123]
  else
    [nil, nil]
  end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _, context = construction.synthesize(source.node)

        assert_no_error typing

        assert_equal parse_type("[::String?, ::Integer?]"), type
        assert_equal parse_type("::String?"), context.type_env[:x]
        assert_equal parse_type("::Integer?"), context.type_env[:y]
      end
    end
  end

  def test_masgn_union_tuple2
    with_checker(<<-RBS) do |checker|
      RBS
      source = parse_ruby(<<-RUBY)
x, y =
  if _ = 123
    ["String", 123]
  else
    [nil]
  end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _, context = construction.synthesize(source.node)

        assert_no_error typing

        assert_equal parse_type("[::String?, ::Integer?]"), type
        assert_equal parse_type("::String?"), context.type_env[:x]
        assert_equal parse_type("::Integer?"), context.type_env[:y]
      end
    end
  end

  def test_self_type_call
    with_checker(<<-RBS) do |checker|
      RBS
      source = parse_ruby(<<-RUBY)
# @type var x: Object
x = self
x = x.itself
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _, context = construction.synthesize(source.node)
        assert_no_error typing
      end
    end
  end

  def test_empty_yield
    with_checker(<<-RBS) do |checker|
class EmptyYield
  def foo: () { (Integer) -> void } -> void
end
      RBS
      source = parse_ruby(<<-RUBY)
class EmptyYield
  def foo
    yield
  end
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _, context = construction.synthesize(source.node)
        assert_typing_error(typing, size: 1) do |errors|
          errors[0].tap do |error|
            assert_instance_of Diagnostic::Ruby::InsufficientPositionalArguments, error
          end
        end
      end
    end
  end

  def test_self_type_binding_proc_with_type_declaration
    with_checker() do |checker|
      source = parse_ruby(<<RUBY)
# @type var callback: ^() [self: String] -> String
callback = -> { self + "" }
RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _ = construction.synthesize(source.node)

        assert_equal parse_type("^() [self: ::String] -> ::String"), type
        assert_no_error typing
      end
    end
  end

  def test_self_type_binding_proc_with_annotation
    with_checker() do |checker|
      source = parse_ruby(<<RUBY)
callback = -> do
  # @type self: String
  self + ""
end
RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _ = construction.synthesize(source.node)

        assert_equal parse_type("^() [self: ::String] -> ::String"), type
        assert_no_error typing
      end
    end
  end

  def test_self_type_binding_block
    with_checker(<<-RBS) do |checker|
class Object
  def instance_eval: [A] { () [self: self] -> A } -> A
end
      RBS
      source = parse_ruby(<<RUBY)
123.instance_eval do
  self + 123
  self
end
RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _ = construction.synthesize(source.node)

        assert_equal parse_type("::Integer"), type
        assert_no_error typing
      end
    end
  end

  def test_self_type_binding_type_parameter
    with_checker(<<-RBS) do |checker|
class TestSelfBinding
  def self.foo: [A] { () [self: instance] -> A } -> A

  @name: String
end
      RBS
      source = parse_ruby(<<RUBY)
TestSelfBinding.foo {
  @name = "123"
  self
}
RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _ = construction.synthesize(source.node)

        assert_equal parse_type("::TestSelfBinding"), type
        assert_no_error typing
      end
    end
  end

  def test_self_type_binding_generic
    with_checker(<<-RBS) do |checker|
class TestSelfBinding
  def self.foo: [A] (A) { () [self: A] -> A } -> A
end
      RBS
      source = parse_ruby(<<RUBY)
TestSelfBinding.foo(123) { self + 1 }
RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _ = construction.synthesize(source.node)

        assert_equal parse_type("::Integer"), type
        assert_no_error typing
      end
    end
  end

  def test_self_type_incompatible
    with_checker(<<-RBS) do |checker|
class TestSelfBinding
  def foo: () { () [self: String] -> void } -> void

  def bar: () { () [self: Object] -> void } -> void
end
      RBS
      source = parse_ruby(<<RUBY)
class TestSelfBinding
  def foo(&block)
    bar(&block)
  end

  def bar(&block)
    foo(&block)
  end
end
RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _ = construction.synthesize(source.node)

        assert_typing_error(typing, size: 1) do |errors|
          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::BlockTypeMismatch, error
            assert_equal parse_type("^() [self: ::Object] -> void"), error.expected
            assert_equal parse_type("^() [self: ::String] -> void"), error.actual
          end
        end
      end
    end
  end

  def test_block_splat_alias
    with_checker(<<-RBS) do |checker|
type foo = [Integer, String]
      RBS
      source = parse_ruby(<<-RUBY)
# @type var array: Array[foo]
array = []

array.each do |x, y|
  x + 1
  y + ""
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _, context = construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_type_narrowing_subclass
    with_checker(<<-RBS) do |checker|
      RBS
      source = parse_ruby(<<-RUBY)
# @type var object: Numeric | String
object = ""

case object
when Integer
  bar = object
else
  baz = object
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _, context = construction.synthesize(source.node)

        assert_no_error typing
        assert_equal parse_type("::Integer | nil"), context.type_env[:bar]
        assert_equal parse_type("::Numeric | ::String | nil"), context.type_env[:baz]
      end
    end
  end

  def test_assertion_as_type
    with_checker(<<-RBS) do |checker|
      RBS
      source = parse_ruby(<<-RUBY)
array = [] #: Array[Integer]
hash = array #: Hash[Symbol, String]
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _, context = construction.synthesize(source.node)

        assert_typing_error(typing, size: 1) do |errors|
          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::FalseAssertion, error
          end
        end

        assert_equal parse_type("::Array[::Integer]"), context.type_env[:array]
        assert_equal parse_type("::Hash[::Symbol, ::String]"), context.type_env[:hash]
      end
    end
  end

  def test_assertion_as_type_fool_success
    with_checker(<<-RBS) do |checker|
        class Pathname
        end
      RBS
      source = parse_ruby(<<-RUBY)
path = nil #: Pathname?
name = 3 #: String?
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _, context = construction.synthesize(source.node)

        assert_typing_error(typing, size: 1) do |errors|
          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::FalseAssertion, error
            assert_equal parse_type("::String?"), error.assertion_type
            assert_equal parse_type("::Integer"), error.node_type
          end
        end

        assert_equal parse_type("::Pathname?"), context.type_env[:path]
        assert_equal parse_type("::String?"), context.type_env[:name]
      end
    end
  end

  def test_type_app_succeed
    with_checker(<<-RBS) do |checker|
class Array[unchecked out Elem]
  def union: [T] (*Array[T]) -> Array[Elem | T]
end
      RBS
      source = parse_ruby(<<-RUBY)
x = [1].union([1.2]) #$ Numeric
y = [1]&.union([""]) #$ Object
z = [1].map { _1.to_s } #$ Object
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _, context = construction.synthesize(source.node)

        assert_no_error typing

        assert_equal parse_type("::Array[::Integer | ::Numeric]"), context.type_env[:x]
        assert_equal parse_type("::Array[::Integer | ::Object]?"), context.type_env[:y]
        assert_equal parse_type("::Array[::Object]"), context.type_env[:z]
      end
    end
  end

  def test_type_app_error
    with_checker(<<-RBS) do |checker|
class AppTest
  def foo: [T < Numeric, S] (T, S) -> [T, S]
end
      RBS
      source = parse_ruby(<<-RUBY)


x = AppTest.new.foo("", 1) #$ String, Integer
y = AppTest.new.foo(1, 2) #$ Integer
z = AppTest.new.foo(1, 2) #$ Integer, Integer, String
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _, context = construction.synthesize(source.node)

        assert_typing_error(typing, size: 3) do |errors|
          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::TypeArgumentMismatchError, error
            assert_equal "Cannot pass a type `::String` as a type parameter `T < ::Numeric`", error.header_line
            assert_equal "String", error.location.source
          end

          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::InsufficientTypeArgument, error
            assert_equal "Requires 2 types, but 1 given: `[T < ::Numeric, S] (T, S) -> [T, S]`", error.header_line
            assert_equal "AppTest.new.foo(1, 2) \#$ Integer", error.location.source
          end

          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::UnexpectedTypeArgument, error
            assert_equal "Unexpected type arg is given to method type `[T < ::Numeric, S] (T, S) -> [T, S]`", error.header_line
            assert_equal "String", error.location.source
          end
        end

        assert_equal parse_type("[untyped, ::Integer]"), context.type_env[:x]
        assert_equal parse_type("[untyped, untyped]"), context.type_env[:y]
        assert_equal parse_type("[untyped, untyped]"), context.type_env[:z]
      end
    end
  end

  def test_class_name_resolution
    with_checker(<<~RBS) do |checker|
        module TestClassConstant
        end

        module Kernel
        end
      RBS
      source = parse_ruby(<<~RUBY)
        module TestClassConstant
          class Integer
          end

          String = true

          module Kernel
          end
        end

        class UnknownOuterModule
          class String
          end
        end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _, context = construction.synthesize(source.node)

        assert_any!(typing.errors) do |error|
          assert_instance_of Diagnostic::Ruby::UnknownConstant, error
          assert_equal :Integer, error.name
          assert_equal :class, error.kind
        end

        assert_any!(typing.errors) do |error|
          assert_instance_of Diagnostic::Ruby::UnknownConstant, error
          assert_equal :String, error.name
          assert_equal :constant, error.kind
        end

        assert_any!(typing.errors) do |error|
          assert_instance_of Diagnostic::Ruby::UnknownConstant, error
          assert_equal :Kernel, error.name
          assert_equal :module, error.kind
        end

        assert_any!(typing.errors) do |error|
          assert_instance_of Diagnostic::Ruby::UnknownConstant, error
          assert_equal :String, error.name
          assert_equal :class, error.kind
        end
      end
    end
  end

  def test_triple_dots_args
    with_checker(<<~RBS) do |checker|
        class TripleDots
          def foo: (Integer, String, foo: String) -> void

          def bar: (Integer, Object, ?foo: String) -> void

          def baz: (Object) -> void
        end
      RBS
      source = parse_ruby(<<~RUBY)
        class TripleDots
          def foo(x, ...)
            bar(123, ...)
            baz(...)
          end

          def bar(...) end
          def baz(...) end
        end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _, context = construction.synthesize(source.node)

        assert_typing_error(typing, size: 1) do |errors|
          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::IncompatibleArgumentForwarding, error
            assert_equal :baz, error.method_name
          end
        end
      end
    end
  end

  def test_triple_dots_block
    with_checker(<<~RBS) do |checker|
        class TripleDots
          def foo: () { (String) -> Object } -> void

          def bar: () ?{ (String) -> Object } -> void

          def baz: () { (Array[Object]) -> Object } -> void
        end
      RBS
      source = parse_ruby(<<~RUBY)
        class TripleDots
          def foo(...)
            bar(...)
            baz(...)
          end

          def bar(...) end
          def baz(...) end
        end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _, context = construction.synthesize(source.node)

        assert_typing_error(typing, size: 1) do |errors|
          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::IncompatibleArgumentForwarding, error
            assert_equal :baz, error.method_name
          end
        end
      end
    end
  end

  def test_flow_sensitive_case_no_cond
    with_checker(<<~RBS) do |checker|
        class TestTest
          attr_reader name: String?

          def next: () -> void
        end
      RBS
      source = parse_ruby(<<~RUBY)
        class TestTest
          # @dynamic name

          def next
            case
            when name
              name.size
            end
          end
        end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _, context = construction.synthesize(source.node)

        assert_no_error(typing)
      end
    end
  end

  def test_untyped_call_block
    with_checker(<<~RBS) do |checker|
      RBS
      source = parse_ruby(<<~RUBY)
        (_ = [1, 2, 3]).each {|i|
          case i
          when 1
            next
          when 2
            next
          when 3
            break
          end
        }
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _, context = construction.synthesize(source.node)

        assert_no_error(typing)
      end
    end
  end

  def test_masgn__global
    with_checker(<<~RBS) do |checker|
        $FOO: String

        $BAR: Integer
      RBS
      source = parse_ruby(<<~RUBY)
        $FOO, $BAR = "1", 2
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _, context = construction.synthesize(source.node)

        assert_no_error(typing)
      end
    end
  end

  def test_opasgn__global
    with_checker(<<~RBS) do |checker|
        $FOO: String
      RBS
      source = parse_ruby(<<~RUBY)
        $FOO += "hoge"
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _, context = construction.synthesize(source.node)

        assert_no_error(typing)
        assert_equal parse_type("::String"), type
      end
    end
  end

  def test_orasgn_andasgn__global
    with_checker(<<~RBS) do |checker|
        $FOO: String
      RBS
      source = parse_ruby(<<~RUBY)
        $FOO ||= "hoge"
        $FOO &&= "huga"
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _, context = construction.synthesize(source.node)

        assert_no_error(typing)
        assert_equal parse_type("::String"), type
      end
    end
  end

  def test_opasgn_error_report
    with_checker(<<~RBS) do |checker|
      RBS
      source = parse_ruby(<<~RUBY)
        x = [1].first

        x += 1
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _, context = construction.synthesize(source.node)

        assert_all!(typing.errors) do |error|
          assert_operator error, :is_a?, Diagnostic::Ruby::NoMethod
          assert_instance_of Parser::Source::Range, error.location
        end
      end
    end
  end

  def test_return__mvalue
    with_checker(<<~RBS) do |checker|
        class ReturnMultipleValues
          def foo: () -> [String, Integer]
        end
      RBS
      source = parse_ruby(<<~RUBY)
        class ReturnMultipleValues
          def foo
            return "foo", 123
          end
        end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _, context = construction.synthesize(source.node)
        assert_no_error(typing)
      end
    end
  end

  def test_masgn__splat_rhs1
    with_checker(<<~RBS) do |checker|
        class WithToA
          def to_a: () -> [Integer, String, bool]
        end
      RBS
      source = parse_ruby(<<~RUBY)
        a, b, c = *WithToA.new
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _, context = construction.synthesize(source.node)
        assert_no_error(typing)
        assert_equal parse_type("::Integer"), context.type_env[:a]
        assert_equal parse_type("::String"), context.type_env[:b]
        assert_equal parse_type("bool"), context.type_env[:c]
      end
    end
  end

  def test_masgn__splat_rhs2
    with_checker(<<~RBS) do |checker|
      RBS
      source = parse_ruby(<<~RUBY)
        a, b = *123
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _, context = construction.synthesize(source.node)
        assert_no_error(typing)
        assert_equal parse_type("::Integer"), context.type_env[:a]
        assert_equal parse_type("nil"), context.type_env[:b]
      end
    end
  end

  def test_masgn__splat_rhs3
    with_checker(<<~RBS) do |checker|
        class WithToA
          def to_a: () -> Array[Integer]
        end
      RBS
      source = parse_ruby(<<~RUBY)
        a, b = *WithToA.new
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _, context = construction.synthesize(source.node)
        assert_no_error(typing)
        assert_equal parse_type("::Integer?"), context.type_env[:a]
        assert_equal parse_type("::Integer?"), context.type_env[:b]
      end
    end
  end

  def test_super__splat_arg
    with_checker(<<~RBS) do |checker|
        class SuperSplatBase
          def foo: (String, *Integer) -> void
        end

        class SuperSplat < SuperSplatBase
          def foo: (*Integer) -> void
        end
      RBS
      source = parse_ruby(<<~RUBY)
        class SuperSplat
          def foo(*is)
            super("foo", *is)
          end
        end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _, context = construction.synthesize(source.node)
        assert_no_error(typing)
      end
    end
  end

  def test_super__splat_arg_untyped
    with_checker(<<~RBS) do |checker|
        class SuperSplatBase
        end

        class SuperSplat < SuperSplatBase
          def foo: (*Integer) -> void
        end
      RBS
      source = parse_ruby(<<~RUBY)
        class SuperSplat
          def foo(*is)
            super(*is)
          end
        end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _, context = construction.synthesize(source.node)

        assert_typing_error(typing, size: 1) do |errors|
          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::UnexpectedSuper, error
          end
        end
      end
    end
  end

  def test_send__type_inference_return
    with_checker(<<~RBS) do |checker|
        class Array[unchecked out A]
          def each: () -> Enumerator[A, void]
                  | ...
        end

        class Enumerator[A, B]
          def each: { (A) -> void } -> B

          def map: [X] () { (A) -> X } -> Array[X]
        end
      RBS
      source = parse_ruby(<<~RUBY)
        # @type var s: Array[[Integer, Integer]]
        s = [1, 2, 3].each.map do |n|
          [n, n]
        end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _, context = construction.synthesize(source.node)

        assert_no_error typing

        assert_equal parse_type("::Array[[::Integer, ::Integer]]"), type
      end
    end
  end

  def test_send_block__untyped_distribute
    with_checker(<<~RBS) do |checker|
        class UntypedBlock
          def self.foo: () { (untyped) -> void } -> void
        end
      RBS
      source = parse_ruby(<<~RUBY)
        UntypedBlock.foo do |x, y, *z|
          x.foo
          y.foo
          z[0].foo
        end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _, context = construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_assertion__ignore_rdoc_directive
    with_checker(<<~RBS) do |checker|
        class RDocCommentConflictTest
        end
      RBS
      source = parse_ruby(<<~RUBY)
        class RDocCommentConflictTest # :nodoc:
        end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _, context = construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_block_pass__to_proc
    with_checker(<<~RBS) do |checker|
        class ToProcTest
          def self.foo: () { (Integer) -> void } -> void
        end

        class ReturnsProc
          def to_proc: () -> (^(Integer) -> String)
        end
      RBS
      source = parse_ruby(<<~RUBY)
        ToProcTest.foo(&ReturnsProc.new)
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _, context = construction.synthesize(source.node)

        assert_no_error typing
      end
    end
  end

  def test_block_pass__to_proc_nil
    with_checker(<<~RBS) do |checker|
        class ToProcTest
          def self.foo: () { (Integer) -> void } -> void
        end

        class ReturnsProc
          def to_proc: () -> nil
        end
      RBS
      source = parse_ruby(<<~RUBY)
        ToProcTest.foo(&ReturnsProc.new)
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _, context = construction.synthesize(source.node)

        assert_typing_error(typing, size: 1) do |errors|
          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::RequiredBlockMissing, error
          end
        end
      end
    end
  end

  def test_block_pass__to_proc_no
    with_checker(<<~RBS) do |checker|
        class ToProcTest
          def self.foo: () { (Integer) -> void } -> void
        end

        class ReturnsProc
        end
      RBS
      source = parse_ruby(<<~RUBY)
        ToProcTest.foo(&ReturnsProc.new)
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _, context = construction.synthesize(source.node)

        assert_typing_error(typing, size: 1) do |errors|
          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::BlockTypeMismatch, error
          end
        end
      end
    end
  end

  def test_type_hint__proc_optional
    with_checker(<<~RBS) do |checker|
      RBS
      source = parse_ruby(<<~RUBY)
        # @type var proc: nil | ^(Integer) -> String
        proc = -> (x) do
          x.hogehoge
        end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _, context = construction.synthesize(source.node)

        assert_typing_error(typing, size: 1) do |errors|
          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::NoMethod, error
            assert_equal parse_type("::Integer"), error.type
          end
        end
      end
    end
  end

  def test_type_hint__proc_union_with_proc
    with_checker(<<~RBS) do |checker|
      RBS
      source = parse_ruby(<<~RUBY)
        # @type var proc: (^(Integer) -> String) | (^(String, String) -> Integer)
        proc = -> (x) do
          x.hogehoge
        end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _, context = construction.synthesize(source.node)

        assert_typing_error(typing, size: 1) do |errors|
          assert_any!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::ProcHintIgnored, error
            assert_equal parse_type("(^(::Integer) -> ::String) | (^(::String, ::String) -> ::Integer)"), error.hint_type
          end
        end
      end
    end
  end

  def test_type_hint__proc_union_proc_instance
    with_checker(<<~RBS) do |checker|
      RBS
      source = parse_ruby(<<~RUBY)
        # @type var proc: Proc
        proc = -> (x) do
          x.hogehoge
        end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _, context = construction.synthesize(source.node)
        assert_no_error typing
      end
    end
  end

  def test_rational_and_complex_literal
    with_checker(<<~RBS) do |checker|
      RBS
      source = parse_ruby(<<~RUBY)
        r = 1r
        c = 1i
        rc = 1ri
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        # type, _, context = construction.synthesize(source.node)
        pair = construction.synthesize(source.node)

        assert_equal parse_type("::Rational"), pair.context.type_env[:r]
        assert_equal parse_type("::Complex"), pair.context.type_env[:c]
        assert_equal parse_type("::Complex"), pair.context.type_env[:rc]
        assert_no_error typing
      end
    end
  end
end
