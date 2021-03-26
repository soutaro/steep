require "test_helper"

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
  LocalVariableTypeEnv = Steep::TypeInference::LocalVariableTypeEnv
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

        assert_equal 1, typing.errors.size
        assert_incompatible_assignment typing.errors[0],
                                       lhs_type: parse_type("::_A"),
                                       rhs_type: parse_type("::_B") do |error|
          assert_equal :lvasgn, error.node.type
          assert_equal :z, error.node.children[0]
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

      with_standard_construction(checker, source) do |construction, typing|
        pair = construction.synthesize(source.node)

        assert_equal parse_type("::Integer"), typing.type_of(node: source.node)

        assert_nil typing.context_at(line: 1, column: 0).lvar_env[:x]
        assert_nil typing.context_at(line: 1, column: 0).lvar_env[:z]

        assert_equal parse_type("::Integer"), typing.context_at(line: 1, column: 5).lvar_env[:x]
        assert_nil typing.context_at(line: 1, column: 5).lvar_env[:z]

        assert_equal parse_type("::Integer"), pair.context.lvar_env[:x]
        assert_equal parse_type("::Integer"), pair.context.lvar_env[:z]

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
        pair = construction.synthesize(source.node)

        assert_equal parse_type("::String"), typing.type_of(node: source.node)

        assert_nil typing.context_at(line: 1, column: 0).lvar_env[:x]
        assert_equal parse_type("::Integer"), typing.context_at(line: 1, column: 5).lvar_env[:x]
        assert_equal parse_type("::String"), pair.context.lvar_env[:x]

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

        assert_equal 1, typing.errors.size
        typing.errors.first.tap do |error|
          assert_instance_of Diagnostic::Ruby::IncompatibleArguments, error
          assert_equal [parse_method_type("(::_A, ?::_B) -> ::_B")], error.method_types
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
a.g(_ = nil, _ = nil, _ = nil)
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal parse_type("::_B"), typing.type_of(node: source.node)

        assert_equal 1, typing.errors.size
        typing.errors.first.tap do |error|
          assert_instance_of Diagnostic::Ruby::IncompatibleArguments, error
          assert_equal [parse_method_type("(::_A, ?::_B) -> ::_B")], error.method_types
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

        assert_equal 1, typing.errors.size

        typing.errors.first.tap do |error|
          assert_instance_of Diagnostic::Ruby::IncompatibleArguments, error
          assert_equal [parse_method_type("(a: ::_A, ?b: ::_B) -> ::_C")], error.method_types
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

        assert_equal 1, typing.errors.size
        typing.errors.first.tap do |error|
          assert_instance_of Diagnostic::Ruby::UnexpectedKeyword, error
          assert_equal Set.new([:c]), error.unexpected_keywords
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
            assert_incompatible_assignment error,
                                           lhs_type: parse_type("::_A"),
                                           rhs_type: parse_type("::_B")
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

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal parse_type("untyped"), typing.type_of(node: dig(source.node, 2))
        assert_equal parse_type("::_A"), typing.context_at(line: 4, column: 0).lvar_env[:x]
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

        refute_empty typing.errors
        assert_incompatible_assignment typing.errors[0],
                                       lhs_type: parse_type("::_C"),
                                       rhs_type: parse_type("::_A | ::_C") do |error|
          assert_equal :optarg, error.node.type
          assert_equal :y, error.node.children[0]
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

        refute_empty typing.errors
        assert_incompatible_assignment typing.errors[0],
                                       lhs_type: parse_type("::_C"),
                                       rhs_type: parse_type("::_A | ::_C") do |error|
          assert_equal :kwoptarg, error.node.type
          assert_equal :y, error.node.children[0]
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

      with_standard_construction(checker, source) do |construction, typing|
        pair = construction.synthesize(source.node)

        assert_equal parse_type("::_X"), pair.context.lvar_env[:a]

        assert_equal parse_type("::_A"), typing.context_at(line: 6, column: 0).lvar_env[:a]
        assert_nil typing.context_at(line: 6, column: 0).lvar_env[:b]

        assert_equal parse_type("::_A"), typing.context_at(line: 7, column: 0).lvar_env[:a]
        assert_equal parse_type("::_A"), typing.context_at(line: 7, column: 0).lvar_env[:b]
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

      with_standard_construction(checker, source) do |construction, typing|
        pair = construction.synthesize(source.node)

        assert_no_error typing

        assert_equal parse_type("::_X"), pair.context.lvar_env[:x]
        assert_nil pair.context.lvar_env[:a]
        assert_nil pair.context.lvar_env[:d]

        block_context = typing.context_at(line: 8, column: 0)
        assert_equal parse_type("::_A"), block_context.lvar_env[:a]
        assert_equal parse_type("::_X"), block_context.lvar_env[:x]
        assert_equal parse_type("::_D"), block_context.lvar_env[:d]
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
        assert_no_error typing
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

        assert_equal parse_type("::_X"), pair.context.lvar_env[:x]
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
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
def foo()
  # @type return: _A
  # @type var a: _A
  a = (_ = nil)
  return a
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

        assert_empty typing.errors
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
            assert_instance_of Diagnostic::Ruby::FallbackAny, error
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

        assert_equal 2, typing.errors.size
        assert_any typing.errors do |error|
          error.is_a?(Diagnostic::Ruby::IncompatibleAssignment) &&
            error.node.type == :ivasgn &&
            error.node.children[0] == :"@x"
        end
        assert_any typing.errors do |error|
          error.is_a?(Diagnostic::Ruby::IncompatibleAssignment) &&
            error.node.type == :lvasgn &&
            error.node.children[1].type == :ivar &&
            error.node.children[1].children[0] == :"@x"
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
        for_class = construction.for_class(source.node)

        assert_equal(
          Annotation::Implements::Module.new(name: TypeName("::Person"), args: []),
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
        for_class = construction.for_class(source.node)

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

      annotations = source.annotations(block: source.node, factory: checker.factory, current_module: Namespace.root)
      const_env = ConstantEnv.new(factory: factory, context: [Namespace.root])
      type_env = TypeEnv.build(annotations: annotations,
                               subtyping: checker,
                               const_env: const_env,
                               signatures: checker.factory.env)
      lvar_env = LocalVariableTypeEnv.empty(
        subtyping: checker,
        self_type: parse_type("singleton(::Steep::Names::Module)"),
        instance_type: parse_type("::Steep"),
        class_type: parse_type("singleton(::Steep)")
      ).annotate(annotations)

      module_context = Context::ModuleContext.new(
        instance_type: parse_type("::Steep"),
        module_type: parse_type("singleton(::Steep)"),
        implement_name: nil,
        current_namespace: Namespace.parse("::Steep"),
        const_env: const_env,
        class_name: nil
      )

      context = Context.new(
        block_context: nil,
        method_context: nil,
        module_context: module_context,
        break_context: nil,
        self_type: nil,
        type_env: type_env,
        lvar_env: lvar_env,
        call_context: MethodCall::TopLevelContext.new
      )
      typing = Typing.new(source: source, root_context: context)

      module_name_class_node = source.node.children[1]

      construction = TypeConstruction.new(checker: checker,
                                          source: source,
                                          annotations: annotations,
                                          context: context,
                                          typing: typing)

      for_module = construction.for_class(module_name_class_node)

      assert_equal(
        Annotation::Implements::Module.new(
          name: TypeName("::Steep::Names::Module"),
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
        for_module = construction.for_module(source.node)

        assert_equal(
          Annotation::Implements::Module.new(name: TypeName("::Steep"), args: []),
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

        for_module = construction.for_module(source.node)

        assert_nil for_module.module_context.implement_name
        assert_nil for_module.module_context.instance_type
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

      annotations = source.annotations(block: source.node, factory: checker.factory, current_module: Namespace.root)
      const_env = ConstantEnv.new(factory: factory, context: [Namespace.root])
      type_env = TypeEnv.build(annotations: annotations,
                               subtyping: checker,
                               const_env: const_env,
                               signatures: checker.factory.env)
      lvar_env = LocalVariableTypeEnv.empty(
        subtyping: checker,
        self_type: parse_type("singleton(::Steep)"),
        instance_type: parse_type("::Steep"),
        class_type: parse_type("singleton(::Steep)")
        )

      module_context = Context::ModuleContext.new(
        instance_type: parse_type("::Steep"),
        module_type: parse_type("singleton(::Steep)"),
        implement_name: nil,
        current_namespace: Namespace.parse("::Steep"),
        const_env: const_env,
        class_name: TypeName("::Steep")
      )

      context = Context.new(
        block_context: nil,
        method_context: nil,
        module_context: module_context,
        break_context: nil,
        self_type: nil,
        type_env: type_env,
        lvar_env: lvar_env,
        call_context: MethodCall::ModuleContext.new(type_name: TypeName("::Steep"))
      )
      typing = Typing.new(source: source, root_context: context)

      module_node = source.node.children.last

      construction = TypeConstruction.new(checker: checker,
                                          source: source,
                                          annotations: annotations,
                                          context: context,
                                          typing: typing)

      for_module = construction.for_module(module_node)

      assert_equal(
        Annotation::Implements::Module.new(name: TypeName("::Steep::Printable"), args: []),
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
        refute method_context.constructor

        assert_equal parse_type("::A"), for_method.self_type
        assert_nil for_method.block_context
        assert_equal Set[:x], for_method.context.lvar_env.vars
        assert_equal parse_type("::String"), for_method.context.lvar_env[:x]
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
        refute method_context.constructor

        assert_equal parse_type("::A"), for_method.self_type
        assert_nil for_method.block_context
        assert_equal parse_type("::Object | ::String"), for_method.context.lvar_env[:x]

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
        refute method_context.constructor

        assert_equal parse_type("::A"), for_method.self_type
        assert_nil for_method.block_context
        assert_empty for_method.context.lvar_env.vars

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
        refute method_context.constructor

        assert_equal parse_type("::A"), for_method.self_type
        assert_nil for_method.block_context
        assert_equal Set[:x], for_method.context.lvar_env.vars
        assert_equal parse_type("::String"), for_method.context.lvar_env[:x]

        assert_equal 1, typing.errors.size
        assert_instance_of Diagnostic::Ruby::MethodReturnTypeAnnotationMismatch, typing.errors.first
      end
    end
  end

  def test_new_method_with_incompatible_annotation
    with_checker <<-EOF do |checker|
class A
  def foo: (String) -> Integer
end
    EOF

      source = parse_ruby(<<-RUBY)
class A
  # @type method foo: (String) -> String
  def foo(x)
    nil
  end
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        def_node = source.node.children[2]
        type_name = parse_type("::A").name
        instance_definition = checker.factory.definition_builder.build_instance(type_name)

        construction.for_new_method(:foo,
                                    def_node,
                                    args: def_node.children[1].children,
                                    self_type: parse_type("::A"),
                                    definition: instance_definition)

        skip "Skip testing if method type annotation is compatible with interface"

        assert_equal 1, typing.errors.size
        assert_instance_of Diagnostic::Ruby::IncompatibleMethodTypeAnnotation, typing.errors.first
      end
    end
  end

  def test_relative_type_name
    with_checker <<-EOF do |checker|
class A::String
  def aaaaa: -> untyped
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

        assert_typing_error(typing, size: 2) do |errors|
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
    x = ::A::String.new
    x = String.new

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
a, @b = 1, 2
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal 2, typing.errors.size
        assert_any typing.errors do |error|
          error.is_a?(Diagnostic::Ruby::IncompatibleAssignment) &&
            error.node.type == :lvasgn
        end
        assert_any typing.errors do |error|
          error.is_a?(Diagnostic::Ruby::IncompatibleAssignment) &&
            error.node.type == :ivasgn
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

        assert_equal parse_type("::String"), pair.context.lvar_env[:a]
        assert_equal parse_type("::Symbol"), pair.context.lvar_env[:c]
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

        assert_equal parse_type("::Integer"), context.lvar_env[:a]
        assert_equal parse_type("::Array[::Integer | ::String]"), context.lvar_env[:b]
        assert_equal parse_type("::Symbol"), context.lvar_env[:c]
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

        assert_equal parse_type("::Integer?"), pair.context.lvar_env[:c]

        assert_equal 2, typing.errors.size
        assert_any typing.errors do |error|
          error.is_a?(Diagnostic::Ruby::IncompatibleAssignment) &&
            error.node.type == :lvasgn &&
            error.rhs_type == parse_type("::Integer?")
        end
        assert_any typing.errors do |error|
          error.is_a?(Diagnostic::Ruby::IncompatibleAssignment) &&
            error.node.type == :ivasgn &&
            error.rhs_type == parse_type("::Integer?")
        end
      end
    end
  end

  def test_masgn_union
    with_checker do |checker|
      source = parse_ruby(<<-RUBY)
# @type var x: Array[Integer] | Array[String]
x = (_ = nil)
a, b = x
      RUBY


      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_no_error typing
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
        assert_equal parse_type("::Integer?"), context.lvar_env[:a]
        assert_equal parse_type("::Array[::Integer]"), context.lvar_env[:b]
        assert_equal parse_type("::Integer?"), context.lvar_env[:c]
      end
    end
  end

  def test_masgn_optional
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
# @type var tuple: [Integer, String]?
tuple = nil
a, b = x = tuple
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        _, _, context = construction.synthesize(source.node)

        assert_no_error typing

        assert_equal parse_type("::Integer?"), context.lvar_env[:a]
        assert_equal parse_type("::String?"), context.lvar_env[:b]
        assert_equal parse_type("[::Integer, ::String]?"), context.lvar_env[:x]
      end
    end
  end

  def test_masgn_optional_conditional
    with_checker do |checker|
      source = parse_ruby(<<-RUBY)
# @type var tuple: [Integer, String]?
tuple = nil
if (a, b = x = tuple)
  a + 1
  b + "a"
else
  return
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        _, _, context = construction.synthesize(source.node)

        assert_no_error typing

        assert_equal parse_type("::Integer"), context.lvar_env[:a]
        assert_equal parse_type("::String"), context.lvar_env[:b]
        assert_equal parse_type("[::Integer, ::String]"), context.lvar_env[:x]
      end
    end
  end

  def test_masgn_untyped
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
a, @b = _ = nil
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal 1, typing.errors.size

        assert_all!(typing.errors) do |error|
          assert_instance_of Diagnostic::Ruby::FallbackAny, error
        end
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
        assert_equal parse_type("::String"), pair.context.lvar_env[:y]
        assert_equal parse_type("::Integer"), pair.context.lvar_env[:z]
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

        assert_empty typing.errors
        assert_equal parse_type("::String | ::Integer"), pair.constr.context.lvar_env[:y]
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

        assert_equal 1, typing.errors.size
        assert_any typing.errors do |error|
          error.is_a?(Diagnostic::Ruby::FallbackAny)
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

        assert_equal parse_type("untyped"), context.lvar_env[:b]
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

        assert_equal 1, typing.errors.size
        assert_any typing.errors do |error|
          error.is_a?(Diagnostic::Ruby::UnexpectedJumpValue)
        end
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

        assert_equal parse_type("::Integer?"), context.lvar_env[:y]
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

        assert_equal 2, typing.errors.size
        assert_any typing.errors do |error|
          error.is_a?(Diagnostic::Ruby::FallbackAny) &&
            error.node == dig(source.node, 1, 0)
        end
        assert_any typing.errors do |error|
          error.is_a?(Diagnostic::Ruby::FallbackAny) &&
            error.node == dig(source.node, 2, 1)
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

        assert_equal 2, typing.errors.size
        assert typing.errors.all? {|error| error.is_a?(Diagnostic::Ruby::FallbackAny) }
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
        assert_equal parse_type("::Array[::Integer|::Symbol|::String]"), pair.context.lvar_env[:b]
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

        assert_equal parse_type("::A"), pair.context.lvar_env[:a]
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

        assert_empty typing.errors
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

        assert_equal 2, typing.errors.size
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

        assert_equal 2, typing.errors.size
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

        assert_equal 1, typing.errors.size
        assert_instance_of Diagnostic::Ruby::IncompatibleAssignment, typing.errors[0]
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
        assert_equal parse_type("::String"), constr.context.lvar_env[:b]
      end
    end
  end

  def test_if_typing
    with_checker do |checker|
      source = parse_ruby(<<EOF)
if 3
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

        assert_equal parse_type("::String | ::Integer"), pair.constr.context.lvar_env[:x]
        assert_equal parse_type("::Integer"), pair.constr.context.lvar_env[:y]
        assert_equal parse_type("::Symbol?"), pair.constr.context.lvar_env[:z]
      end
    end
  end

  def test_if_return
    with_checker do |checker|
      source = parse_ruby(<<-RUBY)
if 3
  return
else
  x = :foo
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        pair = construction.synthesize(source.node)

        assert_empty typing.errors

        assert_equal parse_type("::Symbol"), pair.constr.context.lvar_env[:x]
      end
    end
  end

  def test_if_annotation_success
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type var x: String | Integer
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

        assert_no_error typing

        true_context = typing.context_at(line: 6, column: 3)
        assert_equal parse_type("::String"), true_context.lvar_env[:x]

        true_context = typing.context_at(line: 9, column: 3)
        assert_equal parse_type("::Integer"), true_context.lvar_env[:x]
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
        assert_equal parse_type("::String | ::Integer"), pair.context.lvar_env[:x]
        assert_equal parse_type("::Integer"), pair.context.lvar_env[:y]
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

        assert_empty typing.errors

        assert_equal parse_type("::Integer"), typing.context_at(line: 6, column: 2).lvar_env[:x]
        assert_equal parse_type("::Integer | ::String"), pair.context.lvar_env[:x]
      end
    end
  end

  def test_while_type_error
    with_checker do |checker|
      source = parse_ruby(<<EOF)
x = 3 ? 4 : ""

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
        assert_equal parse_type("::String | ::Integer | ::Symbol | nil"), pair.context.lvar_env[:x]
      end
    end
  end

  def test_rescue_bidning_typing
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
        assert_equal parse_type("::String | ::FalseClass"), context.lvar_env[:x]
        assert_equal parse_type("::String | true"), context.lvar_env[:y]
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
        assert_equal parse_type("::Integer"), pair.constr.context.lvar_env[:y]
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
        assert_equal parse_type("::String | ::Integer | nil"), pair.context.lvar_env[:y]
        assert_equal parse_type("::Symbol"), pair.context.lvar_env[:z]
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
          assert_instance_of Diagnostic::Ruby::ElseOnExhaustiveCase, error
          assert_equal error.node, dig(source.node, 1, 2)
        end

        assert_equal parse_type("::String | ::Integer"), pair.type
        assert_equal parse_type("nil"), pair.context.lvar_env[:z]
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
x = nil

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
x = nil
# @type var y1: Integer
y1 = 3

z = (x && y1 = y = x + 1)
EOF

      with_standard_construction(checker, source) do |construction, typing|
        pair = construction.synthesize(source.node)

        assert_no_error typing

        assert_equal parse_type("::Integer?"), pair.constr.context.lvar_env[:y]
        assert_equal parse_type("::Integer?"), pair.constr.context.lvar_env[:z]
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

        assert_equal parse_type("::Integer"), pair.context.lvar_env[:x]
        assert_equal parse_type("::Integer?"), pair.context.lvar_env[:y]
      end
    end
  end

  def test_csend_unwrap
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type var x: String?
x = nil

z = x&.size()
EOF

      with_standard_construction(checker, source) do |construction, typing|
        pair = construction.synthesize(source.node)

        assert_no_error typing

        assert_equal parse_type("::Integer?"), pair.type
        assert_equal parse_type("::Integer?"), pair.context.lvar_env[:z]
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

      with_standard_construction(checker, source) do |construction, typing|
        pair = construction.synthesize(source.node)

        assert_empty typing.errors

        assert_equal parse_type("::String"), typing.context_at(line: 2, column: 2).lvar_env[:line]

        assert_equal parse_type("::String?"), pair.context.lvar_env[:line]
        assert_equal parse_type("::String?"), pair.context.lvar_env[:x]
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
# @type var x: String | Integer
x = ""

y = case x
    when String
      3
    when Integer
      4
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

        assert_equal 1, typing.errors.size
        typing.errors[0].yield_self do |error|
          assert_instance_of Diagnostic::Ruby::FallbackAny, error
        end
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

        assert_typing_error(typing, size: 1) do |errors|
          assert_any errors do |error|
            error.is_a?(Diagnostic::Ruby::IncompatibleAssignment) &&
              error.rhs_type == parse_type("::Integer") &&
              error.lhs_type == parse_type("::Hash[::Symbol, untyped]")
          end
        end
      end
    end
  end

  def test_splat_kw_args_2
    with_checker <<-EOS do |checker|
class KWArgTest
  def foo: (Integer, **String) -> void
end
    EOS
      source = parse_ruby(<<EOF)
test = KWArgTest.new

params = { a: 123 }
test.foo(123, params)
test.foo(123, 123)
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal 2, typing.errors.size

        assert_any typing.errors do |error|
          error.is_a?(Diagnostic::Ruby::ArgumentTypeMismatch) &&
            error.actual == parse_type("::Hash[::Symbol, ::Integer]") &&
            error.expected == parse_type("::Hash[::Symbol, ::String]")
        end

        assert_any typing.errors do |error|
          error.is_a?(Diagnostic::Ruby::ArgumentTypeMismatch) &&
            error.actual == parse_type("::Integer") &&
            error.expected == parse_type("::Hash[::Symbol, ::String]")
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

        assert_equal parse_type("bool"), pair.context.lvar_env[:a]
        assert_equal parse_type("bool"), pair.context.lvar_env[:b]
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

        assert_equal parse_type('"foo"'), pair.context.lvar_env[:a]
        assert_equal parse_type('"foo"'), pair.context.lvar_env[:b]
        assert_equal parse_type(':bar'), pair.context.lvar_env[:c]
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

        assert_equal parse_type('::Integer'), pair.context.lvar_env[:a]
        assert_equal parse_type('::String'), pair.context.lvar_env[:b]
        assert_equal parse_type('::Integer | ::String'), pair.context.lvar_env[:c]
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

        assert_equal 1, typing.errors.size
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
        assert_equal parse_type('[::String, ::Integer]'), pair.context.lvar_env[:x]
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

        assert_equal parse_type('::String'), pair.context.lvar_env[:x]
        assert_equal parse_type('::Integer'), pair.context.lvar_env[:y]
        assert_equal parse_type('bool'), pair.context.lvar_env[:z]

        assert_equal parse_type('::String'), pair.context.lvar_env[:a]
        assert_equal parse_type('::Integer'), pair.context.lvar_env[:b]

        assert_equal parse_type("nil"), pair.context.lvar_env[:c]
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

        assert_equal parse_type('::Integer'), context.lvar_env[:a]
        assert_equal parse_type('::String'), context.lvar_env[:b]
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
          error.is_a?(Diagnostic::Ruby::FallbackAny)
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
x = nil
# @type var y: untyped
y = _ = nil

a = x || "foo"
b = "foo" || x
c = y || "foo"
EOF

      with_standard_construction(checker, source) do |construction, typing|
        pair = construction.synthesize(source.node)

        assert_no_error typing
        assert_equal parse_type("::String"), pair.context.lvar_env[:a]
        assert_equal parse_type("::String?"), pair.context.lvar_env[:b]
        assert_equal parse_type("untyped"), pair.context.lvar_env[:c]
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

        assert_equal 1, typing.errors.size
        assert_any typing.errors do |error|
          error.is_a?(Diagnostic::Ruby::UnexpectedBlockGiven)
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
        assert_equal parse_type("::Array[::String]"), pair.context.lvar_env[:a]
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

      with_standard_construction(checker, source) do |construction, typing|
        pair = construction.synthesize(source.node)

        assert_no_error typing
        assert_equal "^(::Integer, untyped) -> ::Integer", pair.context.lvar_env[:l].to_s

        lambda_context = typing.context_at(line: 3, column: 3)
        assert_equal parse_type("::Integer"), lambda_context.lvar_env[:x]
        assert_equal parse_type("untyped"), lambda_context.lvar_env[:y]
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

        assert_equal 1, typing.errors.size
        typing.errors[0].yield_self do |error|
          assert_instance_of Diagnostic::Ruby::IncompatibleAssignment, error
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
        assert_equal parse_type("nil"), pair.context.lvar_env[:a]
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
        assert_equal parse_type(":foo"), pair.context.lvar_env[:a]
        assert_equal parse_type("::Symbol"), pair.context.lvar_env[:x]
        assert_equal parse_type(":foo"), pair.context.lvar_env[:y]
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
  def self.f: [A] ({ foo: A }) -> A
end
    EOF
      source = parse_ruby(<<EOF)
WithHashArg.f(foo: 3)
EOF

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_empty typing.errors
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

        assert_empty typing.errors
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

        assert_equal 1, typing.errors.size
        assert_any typing.errors do |error|
          error.is_a?(Diagnostic::Ruby::NoMethod)
        end
      end
    end
  end

  def test_private_method2
    with_checker <<-EOF do |checker|
class WithPrivate
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

        assert_no_error typing
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

        assert_typing_error(typing, size: 1) do |errors|
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
x = nil
y = x || []
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        pair = construction.synthesize(source.node)

        assert_no_error typing
        assert_equal parse_type("::Array[::Integer]?"), pair.context.lvar_env[:x]
        assert_equal parse_type("::Array[::Integer]"), pair.context.lvar_env[:y]
      end
    end
  end

  def test_or_nil_unwrap2
    with_checker do |checker|
      source = parse_ruby(<<-EOF)
# @type var x: Array[Integer]?
# @type var y: Array[Integer]?
# @type var z: Array[Integer]
x = nil
y = nil
z = x || y || []
      EOF

      with_standard_construction(checker, source) do |construction, typing|
        pair = construction.synthesize(source.node)

        assert_no_error typing
        assert_equal parse_type("::Array[::Integer]?"), pair.context.lvar_env[:x]
        assert_equal parse_type("::Array[::Integer]?"), pair.context.lvar_env[:y]
        assert_equal parse_type("::Array[::Integer]"), pair.context.lvar_env[:z]
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

        assert_no_error(typing)
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

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)
        assert_empty typing.errors

        # a = ...
        typing.context_at(line: 0, column: 0).tap do |ctx|
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

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)
        assert_no_error typing

        # class Hello
        typing.context_at(line: 5, column: 2).tap do |ctx|
          assert_instance_of Context, ctx
          assert_equal "::Hello", ctx.module_context.class_name.to_s
          assert_nil ctx.method_context
          assert_nil ctx.block_context
          assert_nil ctx.break_context
          assert_equal parse_type("singleton(::Hello)"), ctx.self_type
          assert_equal parse_type("::String"), ctx.lvar_env[:a]
          assert_equal parse_type("::Symbol"), ctx.lvar_env[:b]
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

        assert_equal parse_type("::Integer"), context.lvar_env[:a]
        assert_equal parse_type("::Integer"), context.lvar_env[:b]
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
test = nil
test&.foo(x = "", y = x + "")
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        _, _, context = construction.synthesize(source.node)

        assert_no_error typing

        assert_equal parse_type("::String?"), context.lvar_env[:x]
        assert_equal parse_type("::String?"), context.lvar_env[:y]
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

  def test_and_occurence
    with_checker do |checker|
      source = parse_ruby(<<EOF)
(x = [1,nil][0]) && x + 1

y = x and return
EOF

      with_standard_construction(checker, source) do |construction, typing|
        _, _, context = construction.synthesize(source.node)

        assert_no_error typing

        assert_equal parse_type("nil"), context.lvar_env[:x]
        assert_equal parse_type("nil"), context.lvar_env[:y]
      end
    end
  end

  def test_or_occurence
    with_checker do |checker|
      source = parse_ruby(<<EOF)
x = [1,nil][0]
y = x
y or return
EOF

      with_standard_construction(checker, source) do |construction, typing|
        _, _, context = construction.synthesize(source.node)

        assert_no_error typing

        assert_equal parse_type("::Integer?"), context.lvar_env[:x]
        assert_equal parse_type("::Integer"), context.lvar_env[:y]
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
  def self.open: [A] { () -> A } -> A
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
        class_constr = construction.for_class(source.node)
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
        assert_instance_of Diagnostic::Ruby::IncompatibleAssignment, typing.errors[0]
      end
    end
  end

  def test_singleton_class_for_object_success
    with_checker <<-'RBS' do |checker|
class WithSingleton
  def open: [A] { () -> A } -> A
end
    RBS
      source = parse_ruby(<<-'RUBY')
class <<(WithSingleton.new)
  def open
    yield new()
  end
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        type, _ = construction.synthesize(dig(source.node, 0))
        sclass_constr = construction.for_sclass(dig(source.node), type)

        module_context = sclass_constr.context.module_context

        assert_equal parse_type("::WithSingleton"), module_context.instance_type
        assert_equal parse_type("singleton(::WithSingleton)"), module_context.module_type
        assert_equal TypeName("::Object"), module_context.class_name
        assert_nil module_context.implement_name
        assert_equal TypeName("::WithSingleton"), module_context.module_definition.type_name
        assert_equal TypeName("::WithSingleton"), module_context.instance_definition.type_name

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
            assert_instance_of Diagnostic::Ruby::MethodArityMismatch, error
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

        assert_all!(typing.errors) do |error|
          assert_instance_of Diagnostic::Ruby::FallbackAny, error
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

x = 1 ? "" : nil
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
x = WhenUnion.new.map(case 1
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
        assert_equal parse_type("::Integer | ::String"), context.lvar_env[:x]
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
        assert_equal parse_type("::Range[::Integer?]"), context.lvar_env[:a]
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

        assert_no_error typing
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
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_equal 1, typing.errors.size
        assert_instance_of Diagnostic::Ruby::UnsupportedSyntax, typing.errors[0]
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
return if x
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
        assert_equal 1, typing.errors.size
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
        assert_equal 1, typing.errors.size
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

        assert_equal 1, typing.errors.size
        assert_instance_of Diagnostic::Ruby::IncompatibleAnnotation, typing.errors[0]
      end
    end
  end

  def test_case_when_flow_sensitive_bug
    with_checker(<<-RBS) do |checker|
    RBS
      source = parse_ruby(<<-RUBY)
# @type var version: String?
version = nil
# @type var optional_path: String?
optional_path = nil

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

        assert_equal parse_type("untyped"), constr.context.lvar_env[:x]
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

        assert_equal parse_type("untyped"), constr.context.lvar_env[:x]
        assert_equal parse_type("untyped"), constr.context.lvar_env[:y]

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
          assert_instance_of Diagnostic::Ruby::IncompatibleArguments, call.errors[0]
        end

        assert_equal parse_type("::String"), constr.context.lvar_env[:x]
        assert_equal parse_type("::String"), constr.context.lvar_env[:y]
        assert_equal parse_type("::String"), constr.context.lvar_env[:z]
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
          assert_instance_of Diagnostic::Ruby::IncompatibleArguments, call.errors[0]
        end

        assert_equal parse_type("::String"), constr.context.lvar_env[:x]
        assert_equal parse_type("::String"), constr.context.lvar_env[:y]
        assert_equal parse_type("::String"), constr.context.lvar_env[:z]
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

        assert_equal 4, typing.errors.size

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

          assert_equal 1, call.errors.size
        end

        assert_equal parse_type("::String"), constr.context.lvar_env[:x]
        assert_equal parse_type("::String"), constr.context.lvar_env[:y]
        assert_equal parse_type("::String"), constr.context.lvar_env[:z]
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
RBS
      source = parse_ruby(<<-RUBY)
# @type var test: SendTest
test = _ = nil

test.foo do |(x, y)|
end
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        _, constr = construction.synthesize(source.node)

        assert_equal 1, typing.errors.size

        dig(source.node, 1).tap do |call_node|
          call = typing.call_of(node: call_node)
          assert_instance_of MethodCall::Error, call

          assert_equal parse_type("::Array[untyped]"), call.return_type

          assert_equal 1, call.errors.size
          assert_instance_of Diagnostic::Ruby::UnsupportedSyntax, call.errors[0]
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

        assert_equal parse_type("::_YieldUntyped"), pair.context.lvar_env[:x]
        assert_equal parse_type("untyped"), pair.context.lvar_env[:r]
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
a = { foo: "hello", bar: 42, baz: nil }

x = a[:foo]
y = a[:bar]
z = a[:baz]
      RUBY

      with_standard_construction(checker, source) do |construction, typing|
        _, _, context = construction.synthesize(source.node)

        assert_no_error typing

        assert_equal parse_type("::String"), context.lvar_env[:x]
        assert_equal parse_type("::Integer?"), context.lvar_env[:y]
        assert_equal parse_type("::Symbol?"), context.lvar_env[:z]
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

        assert_equal parse_type("::Array[{ foo: ::String, bar: ::Integer }]"), context.lvar_env[:x]
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
        assert_equal parse_type("::String"), context.lvar_env[:a]
      end
    end
  end

  def test_type_case_case_selector
    with_checker do |checker|
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
        assert_equal parse_type("::String"), context.lvar_env[:a]
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
        assert_equal parse_type("::String"), context.lvar_env[:a]
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

        assert_equal parse_type("::String | ::Float | nil"), context.lvar_env[:a]
        assert_equal parse_type("::Symbol | ::Integer | nil"), context.lvar_env[:b]
      end
    end
  end

  def test_and_nested
    with_checker do |checker|
      source = parse_ruby(<<EOF)
# @type var x: String | Float
# @type var y: String?
x = ""
y = nil

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

        assert_equal parse_type("::String | ::Float | nil"), context.lvar_env[:a]
        assert_equal parse_type("::Symbol | ::Integer | nil"), context.lvar_env[:b]
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

  def test_proc_with_block
    skip "Lambda cannot have proc type with block yet..."

    with_checker() do |checker|
      source = parse_ruby(<<RUBY)
# @type var f: ^(Integer) { (String) -> void } -> Array[String]
f = -> (n, &b) { b["foo"]; ["bar"] }
RUBY

      with_standard_construction(checker, source) do |construction, typing|
        construction.synthesize(source.node)

        assert_no_error typing
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

        assert_typing_error(typing, size: 1) do |errors|
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
            assert_instance_of Diagnostic::Ruby::BreakTypeMismatch, error
            assert_equal parse_type("nil"), error.actual
            assert_equal parse_type("::String"), error.expected
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

        assert_typing_error(typing, size: 1) do |errors|
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
x = nil 

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
        type, _ = construction.synthesize(source.node)

        assert_typing_error(typing, size: 2) do |errors|
          assert_all!(errors) do |error|
            assert_instance_of Diagnostic::Ruby::FallbackAny, error
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
        assert_no_error typing
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
end
