require "test_helper"

class TypeConstructionTest < Minitest::Test
  Source = Steep::Source
  Subtyping = Steep::Subtyping
  Typing = Steep::Typing
  TypeConstruction = Steep::TypeConstruction
  Parser = Steep::Parser
  Annotation = Steep::AST::Annotation
  Types = Steep::AST::Types
  Interface = Steep::Interface
  TypeName = Steep::TypeName
  Signature = Steep::AST::Signature
  TypeInference = Steep::TypeInference
  ConstantEnv = Steep::TypeInference::ConstantEnv

  include TestHelper
  include TypeErrorAssertions

  BUILTIN = <<-EOS
class BasicObject
end

class Object <: BasicObject
  def class: -> module
  def tap: { (instance) -> any } -> instance
end

class Class<'a>
end

class Module
  def block_given?: -> any
end

class String
  def to_str: -> String
  def +: (String) -> String
end

class Integer
  def to_int: -> Integer
end

class Range<'a>
  def begin: -> 'a
  def end: -> 'a
end

class Regexp
end

class Array<'a>
  def each: { ('a) -> any } -> self
end
  EOS

  DEFAULT_SIGS = <<-EOS
interface _A
  def +: (_A) -> _A
end

interface _B
end

interface _C
  def f: () -> _A
  def g: (_A, ?_B) -> _B
  def h: (a: _A, ?b: _B) -> _C
end

interface _D
  def foo: () -> any
end

interface _X
  def f: () { (_A) -> _D } -> _C 
end

interface _Kernel
  def foo: (_A) -> _B
         | (_C) -> _D
end

interface _PolyMethod
  def snd: <'a>(any, 'a) -> 'a
  def try: <'a> { (any) -> 'a } -> 'a
end

module Foo<'a>
end
  EOS

  def checker(sigs = DEFAULT_SIGS)
    signatures = Signature::Env.new.tap do |env|
      parse_signature(BUILTIN).each do |sig|
        env.add sig
      end

      parse_signature(sigs).each do |sig|
        env.add sig
      end
    end

    builder = Interface::Builder.new(signatures: signatures)
    Subtyping::Check.new(builder: builder)
  end

  def test_lvar_with_annotation
    source = parse_ruby(<<-EOF)
# @type var x: _A
x = nil
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker()

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        var_types: {},
                                        self_type: nil,
                                        block_context: nil,
                                        typing: typing,
                                        method_context: nil,
                                        module_context: nil,
                                        break_context: nil)
    construction.synthesize(source.node)

    assert_equal Types::Name.new_interface(name: :_A), typing.type_of(node: source.node)
    assert_empty typing.errors
  end

  def test_lvar_with_annotation_type_check
    source = parse_ruby(<<-EOF)
# @type var x: _B
# @type var z: _A
x = nil
z = x
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker()

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        var_types: {},
                                        self_type: nil,
                                        typing: typing,
                                        block_context: nil,
                                        method_context: nil,
                                        module_context: nil,
                                        break_context: nil)
    construction.synthesize(source.node)

    assert_equal Types::Name.new_interface(name: :_A), typing.type_of(node: source.node)

    assert_equal 1, typing.errors.size
    assert_incompatible_assignment typing.errors[0],
                                   lhs_type: Types::Name.new_interface(name: :_A),
                                   rhs_type: Types::Name.new_interface(name: :_B) do |error|
      assert_equal :lvasgn, error.node.type
      assert_equal :z, error.node.children[0].name
    end
  end

  def test_lvar_without_annotation
    source = parse_ruby(<<-EOF)
x = 1
z = x
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker()

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        var_types: {},
                                        block_context: nil,
                                        self_type: nil,
                                        typing: typing,
                                        method_context: nil,
                                        module_context: nil,
                                        break_context: nil)
    construction.synthesize(source.node)

    assert_equal Types::Name.new_instance(name: "::Integer"), typing.type_of(node: source.node)
    assert_empty typing.errors
  end

  def test_lvar_without_annotation_inference
    source = parse_ruby(<<-EOF)
# @type var x: _A
x = nil
z = x
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker()

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        var_types: {},
                                        block_context: nil,
                                        self_type: nil,
                                        typing: typing,
                                        method_context: nil,
                                        module_context: nil,
                                        break_context: nil)
    construction.synthesize(source.node)

    assert_equal Types::Name.new_interface(name: :_A), typing.type_of(node: source.node)
    assert_empty typing.errors
  end

  def test_method_call
    source = parse_ruby(<<-EOF)
# @type var x: _C
x = nil
x.f
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker()

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        var_types: {},
                                        block_context: nil,
                                        self_type: nil,
                                        typing: typing,
                                        method_context: nil,
                                        module_context: nil,
                                        break_context: nil)
    construction.synthesize(source.node)

    assert_equal Types::Name.new_interface(name: :_A), typing.type_of(node: source.node)
    assert_empty typing.errors
  end

  def test_method_call_with_argument
    source = parse_ruby(<<-EOF)
# @type var x: _C
# @type var y: _A
x = nil
y = nil
x.g(y)
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker()

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        var_types: {},
                                        block_context: nil,
                                        self_type: nil,
                                        typing: typing,
                                        method_context: nil,
                                        module_context: nil,
                                        break_context: nil)
    construction.synthesize(source.node)

    assert_equal Types::Name.new_interface(name: :_B), typing.type_of(node: source.node)
    assert_empty typing.errors
  end

  def test_method_call_incompatible_argument_type
    source = parse_ruby(<<-EOF)
# @type var x: _C
# @type var y: _B
x = nil
y = nil
x.g(y)
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker()

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        var_types: {},
                                        block_context: nil,
                                        self_type: nil,
                                        typing: typing,
                                        method_context: nil,
                                        module_context: nil,
                                        break_context: nil)
    construction.synthesize(source.node)

    assert_equal Types::Any.new, typing.type_of(node: source.node)

    assert_equal 1, typing.errors.size
    assert_argument_type_mismatch typing.errors[0],
                                  expected: Types::Name.new_interface(name: :_A),
                                  actual: Types::Name.new_interface(name: :_B)
  end

  def test_method_call_no_error_if_any
    source = parse_ruby(<<-EOF)
x = nil
x.no_such_method
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)

    construction = TypeConstruction.new(checker: checker(),
                                        source: source,
                                        annotations: annotations,
                                        var_types: {},
                                        block_context: nil,
                                        self_type: nil,
                                        typing: typing,
                                        method_context: nil,
                                        module_context: nil,
                                        break_context: nil)
    construction.synthesize(source.node)

    assert_equal Types::Any.new, typing.type_of(node: source.node)
    assert_empty typing.errors
  end

  def test_method_call_no_method_error
    source = parse_ruby(<<-EOF)
# @type var x: _C
x = nil
x.no_such_method
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker()

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        var_types: {},
                                        block_context: nil,
                                        self_type: nil,
                                        typing: typing,
                                        method_context: nil,
                                        module_context: nil,
                                        break_context: nil)
    construction.synthesize(source.node)

    assert_equal Types::Any.new, typing.type_of(node: source.node)

    assert_equal 1, typing.errors.size
    assert_no_method_error typing.errors.first, method: :no_such_method, type: Types::Name.new_interface(name: :_C)
  end

  def test_method_call_missing_argument
    source = parse_ruby(<<-EOF)
# @type var x: _A
# @type var a: _C
a = nil
x = nil
a.g()
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker()

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        var_types: {},
                                        block_context: nil,
                                        self_type: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)
    construction.synthesize(source.node)

    assert_equal Types::Any.new, typing.type_of(node: source.node)

    assert_equal 1, typing.errors.size
    typing.errors.first.tap do |error|
      assert_instance_of Steep::Errors::IncompatibleArguments, error
      assert_equal "(_A, ?_B) -> _B", error.method_type.location.source
    end
  end

  def test_method_call_extra_args
    source = parse_ruby(<<-EOF)
# @type var x: _A
# @type var a: _C
a = nil
x = nil
a.g(nil, nil, nil)
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker()

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        var_types: {},
                                        block_context: nil,
                                        self_type: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)
    construction.synthesize(source.node)

    assert_equal Types::Any.new, typing.type_of(node: source.node)

    assert_equal 1, typing.errors.size
    typing.errors.first.tap do |error|
      assert_instance_of Steep::Errors::IncompatibleArguments, error
      assert_equal "(_A, ?_B) -> _B", error.method_type.location.source
    end
  end

  def test_keyword_call
    source = parse_ruby(<<-EOF)
# @type var x: _C
# @type var a: _A
# @type var b: _B
x = nil
a = nil
b = nil
x.h(a: a, b: b)
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker()

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        var_types: {},
                                        block_context: nil,
                                        self_type: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)
    construction.synthesize(source.node)

    assert_equal Types::Name.new_interface(name: :_C), typing.type_of(node: source.node)
    assert_empty typing.errors
  end

  def test_keyword_missing
    source = parse_ruby(<<-EOF)
# @type var x: _C
x = nil
x.h()
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker()

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        var_types: {},
                                        block_context: nil,
                                        self_type: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)
    construction.synthesize(source.node)

    assert_equal Types::Any.new, typing.type_of(node: source.node)

    assert_equal 1, typing.errors.size

    typing.errors.first.tap do |error|
      assert_instance_of Steep::Errors::IncompatibleArguments, error
      assert_equal "(a: _A, ?b: _B) -> _C", error.method_type.location.source
    end
  end

  def test_extra_keyword_given
    source = parse_ruby(<<-EOF)
# @type var x: _C
x = nil
x.h(a: nil, b: nil, c: nil)
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker()

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        var_types: {},
                                        block_context: nil,
                                        self_type: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)
    construction.synthesize(source.node)

    assert_equal Types::Any.new, typing.type_of(node: source.node)

    assert_equal 1, typing.errors.size
    typing.errors.first.tap do |error|
      assert_instance_of Steep::Errors::IncompatibleArguments, error
      assert_equal "(a: _A, ?b: _B) -> _C", error.method_type.location.source
    end
  end

  def test_keyword_typecheck
    source = parse_ruby(<<-EOF)
# @type var x: _C
# @type var y: _B
x = nil
y = nil
x.h(a: y)
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker()

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        var_types: {},
                                        block_context: nil,
                                        self_type: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)
    construction.synthesize(source.node)

    assert_equal Types::Any.new, typing.type_of(node: source.node)

    assert_equal 1, typing.errors.size
    assert_argument_type_mismatch typing.errors[0],
                                  expected: Types::Name.new_interface(name: :_A),
                                  actual: Types::Name.new_interface(name: :_B)
  end

  def test_def_no_params
    source = parse_ruby(<<-EOF)
def foo
  # @type var x: _A
  x = nil
end
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker()

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        var_types: {},
                                        block_context: nil,
                                        self_type: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)
    construction.synthesize(source.node)

    def_body = source.node.children[2]
    assert_equal Types::Name.new_interface(name: :_A), typing.type_of(node: def_body)
  end

  def test_def_param
    source = parse_ruby(<<-EOF)
def foo(x)
  # @type var x: _A
  y = x
end
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker()

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        var_types: {},
                                        block_context: nil,
                                        self_type: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)
    construction.synthesize(source.node)

    def_body = source.node.children[2]
    assert_equal Types::Name.new_interface(name: :_A), typing.type_of(node: def_body)
    assert_equal Types::Name.new_interface(name: :_A), typing.type_of_variable(name: :x)
    assert_equal Types::Name.new_interface(name: :_A), typing.type_of_variable(name: :y)
  end

  def test_def_param_error
    source = parse_ruby(<<-EOF)
def foo(x, y = x)
  # @type var x: _A
  # @type var y: _C
end
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker()

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        var_types: {},
                                        block_context: nil,
                                        self_type: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)
    construction.synthesize(source.node)

    refute_empty typing.errors
    assert_incompatible_assignment typing.errors[0],
                                   lhs_type: Types::Name.new_interface(name: :_C),
                                   rhs_type: Types::Name.new_interface(name: :_A) do |error|
      assert_equal :optarg, error.node.type
      assert_equal :y, error.node.children[0].name
    end

    assert_equal Types::Name.new_interface(name: :_A), typing.type_of_variable(name: :x)
    assert_equal Types::Name.new_interface(name: :_C), typing.type_of_variable(name: :y)
  end

  def test_def_kw_param_error
    source = parse_ruby(<<-EOF)
def foo(x:, y: x)
  # @type var x: _A
  # @type var y: _C
end
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker()

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        var_types: {},
                                        block_context: nil,
                                        self_type: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)
    construction.synthesize(source.node)

    refute_empty typing.errors
    assert_incompatible_assignment typing.errors[0],
                                   lhs_type: Types::Name.new_interface(name: :_C),
                                   rhs_type: Types::Name.new_interface(name: :_A) do |error|
      assert_equal :kwoptarg, error.node.type
      assert_equal :y, error.node.children[0].name
    end

    assert_equal Types::Name.new_interface(name: :_A), typing.type_of_variable(name: :x)
    assert_equal Types::Name.new_interface(name: :_C), typing.type_of_variable(name: :y)
  end

  def test_block
    source = parse_ruby(<<-EOF)
# @type var a: _X
a = nil

b = a.f do |x|
  # @type var x: _A
  # @type var y: _B
  y = nil
end
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker()

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        var_types: {},
                                        block_context: nil,
                                        self_type: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)
    construction.synthesize(source.node)

    assert_equal Types::Name.new_interface(name: :_X), typing.type_of_variable(name: :a)
    assert_equal Types::Name.new_interface(name: :_C), typing.type_of_variable(name: :b)
    assert_equal Types::Name.new_interface(name: :_A), typing.type_of_variable(name: :x)
    assert_equal Types::Name.new_interface(name: :_B), typing.type_of_variable(name: :y)
  end

  def test_block_shadow
    source = parse_ruby(<<-EOF)
# @type var a: _X
a = nil

a.f do |a|
  # @type var a: _A
  b = a
end
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker()

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        var_types: {},
                                        block_context: nil,
                                        self_type: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)
    construction.synthesize(source.node)

    assert_any typing.var_typing do |var, type| var.name == :a && type.is_a?(Types::Name) && type.name == TypeName::Interface.new(name: :_A) end
    assert_any typing.var_typing do |var, type| var.name == :a && type.is_a?(Types::Name) && type.name == TypeName::Interface.new(name: :_X) end
    assert_equal Types::Name.new_interface(name: :_A), typing.type_of_variable(name: :b)
  end

  def test_block_param_type
    source = parse_ruby(<<-EOF)
# @type var x: _X
x = nil

x.f do |a|
  # @type var d: _D
  d = nil
end
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker()

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        var_types: {},
                                        block_context: nil,
                                        self_type: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)
    construction.synthesize(source.node)

    assert_equal Types::Name.new_interface(name: :_X), typing.type_of_variable(name: :x)
    assert_equal Types::Name.new_interface(name: :_A), typing.type_of_variable(name: :a)
    assert_equal Types::Name.new_interface(name: :_D), typing.type_of_variable(name: :d)
    assert_empty typing.errors
  end

  def test_block_value_type
    source = parse_ruby(<<-EOF)
# @type var x: _X
x = nil

x.f do |a|
  a
end
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker()

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        var_types: {},
                                        block_context: nil,
                                        self_type: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)
    construction.synthesize(source.node)

    assert_equal Types::Name.new_interface(name: :_X), typing.type_of_variable(name: :x)
    assert_equal Types::Name.new_interface(name: :_A), typing.type_of_variable(name: :a)

    assert_equal 1, typing.errors.size
    assert_block_type_mismatch typing.errors[0], expected: Types::Name.new_interface(name: :_D), actual: Types::Name.new_interface(name: :_A)
  end

  def test_block_break_type
    source = parse_ruby(<<-EOF)
# @type var x: _X
x = nil

x.f do |a|
  break a
  # @type var d: _D
  d = nil
end
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker()

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        var_types: {},
                                        block_context: nil,
                                        self_type: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)
    construction.synthesize(source.node)

    assert_equal Types::Name.new_interface(name: :_X), typing.type_of_variable(name: :x)
    assert_equal Types::Name.new_interface(name: :_A), typing.type_of_variable(name: :a)

    assert_equal 1, typing.errors.size
    assert_break_type_mismatch typing.errors[0], expected: Types::Name.new_interface(name: :_C), actual: Types::Name.new_interface(name: :_A)
  end

  def test_return_type
    source = parse_ruby(<<-EOF)
def foo()
  # @type return: _A
  # @type var a: _A
  a = nil
  return a
end
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker()

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        var_types: {},
                                        block_context: nil,
                                        self_type: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)
    construction.synthesize(source.node)

    assert_empty typing.errors
  end

  def test_return_error
    source = parse_ruby(<<-EOF)
def foo()
  # @type return: _X
  # @type var a: _A
  a = nil
  return a
end
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker()

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        var_types: {},
                                        block_context: nil,
                                        self_type: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)
    construction.synthesize(source.node)

    assert_any typing.errors do |error|
      error.is_a?(Steep::Errors::ReturnTypeMismatch) && error.expected == Types::Name.new_interface(name: :_X) && error.actual == Types::Name.new_interface(name: :_A)
    end
  end

  def test_constant_annotation
    source = parse_ruby(<<-EOF)
# @type const Hello: Integer
# @type var hello: Integer
hello = Hello
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker()

    env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)

    module_context = TypeConstruction::ModuleContext.new(
      instance_type: nil,
      module_type: nil,
      const_types: annotations.const_types,
      implement_name: nil,
      current_namespace: nil,
      const_env: env
    )

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        var_types: {},
                                        block_context: nil,
                                        self_type: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: module_context,
                                        break_context: nil)
    construction.synthesize(source.node)

    assert_empty typing.errors
  end

  def test_constant_annotation2
    source = parse_ruby(<<-EOF)
# @type const Hello::World: Integer
Hello::World = ""
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker()

    env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)

    module_context = TypeConstruction::ModuleContext.new(
      instance_type: nil,
      module_type: nil,
      const_types: annotations.const_types,
      implement_name: nil,
      current_namespace: nil,
      const_env: env
    )

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        var_types: {},
                                        block_context: nil,
                                        self_type: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: module_context,
                                        break_context: nil)
    construction.synthesize(source.node)

    assert_any typing.errors do |error|
      error.is_a?(Steep::Errors::IncompatibleAssignment)
    end
  end

  def test_constant_signature
    source = parse_ruby(<<-EOF)
# @type var x: String
x = String
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker()

    env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)

    module_context = TypeConstruction::ModuleContext.new(
      instance_type: nil,
      module_type: nil,
      const_types: annotations.const_types,
      implement_name: nil,
      current_namespace: nil,
      const_env: env
    )

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        var_types: {},
                                        block_context: nil,
                                        self_type: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: module_context,
                                        break_context: nil)
    construction.synthesize(source.node)

    assert_any typing.errors do |error|
      error.is_a?(Steep::Errors::IncompatibleAssignment)
    end
  end

  def test_constant_signature2
    source = parse_ruby(<<-EOF)
X = 3
# @type var x: String
x = X
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker(<<-EOF)
X: Module
    EOF

    env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)

    module_context = TypeConstruction::ModuleContext.new(
      instance_type: nil,
      module_type: nil,
      const_types: annotations.const_types,
      implement_name: nil,
      current_namespace: nil,
      const_env: env
    )

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        var_types: {},
                                        block_context: nil,
                                        self_type: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: module_context,
                                        break_context: nil)
    construction.synthesize(source.node)

    assert_equal 2, typing.errors.size
    assert typing.errors.all? {|error| error.is_a?(Steep::Errors::IncompatibleAssignment) }
  end

  def test_union_method
    source = parse_ruby(<<-EOF)
# @type var k: _Kernel
# @type var a: _A
# @type var c: _C
k = nil
a = nil
c = nil

# @type var b: _B
# b = k.foo(a)

# @type var d: _D
d = k.foo(c)
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker()

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        var_types: {},
                                        block_context: nil,
                                        self_type: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)
    construction.synthesize(source.node)

    assert_empty typing.errors
  end

  def test_ivar_types
    source = parse_ruby(<<-EOF)
def foo
  # @type ivar @x: _A
  # @type var y: _D
  
  y = nil
  
  @x = y
  y = @x
end
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker()

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        var_types: {},
                                        block_context: nil,
                                        self_type: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)
    construction.synthesize(source.node)

    assert_equal 2, typing.errors.size
    assert_any typing.errors do |error|
      error.is_a?(Steep::Errors::IncompatibleAssignment) &&
        error.node.type == :ivasgn &&
        error.node.children[0] == :"@x"
    end
    assert_any typing.errors do |error|
      error.is_a?(Steep::Errors::IncompatibleAssignment) &&
        error.node.type == :lvasgn &&
        error.node.children[1].type == :ivar &&
        error.node.children[1].children[0] == :"@x"
    end
  end

  def test_poly_method_arg
    source = parse_ruby(<<-EOF)
# @type var poly: _PolyMethod
poly = nil

# @type var string: String
string = poly.snd(1, "a")
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker()

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        var_types: {},
                                        block_context: nil,
                                        self_type: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)
    construction.synthesize(source.node)

    assert_empty typing.errors
  end

  def test_poly_method_block
    source = parse_ruby(<<-EOF)
# @type var poly: _PolyMethod
poly = nil

# @type var string: String
string = poly.try { "string" }
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker()

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        var_types: {},
                                        block_context: nil,
                                        self_type: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)
    construction.synthesize(source.node)

    assert_empty typing.errors
  end

  def test_union_type
    source = parse_ruby("1")

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker()

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        var_types: {},
                                        block_context: nil,
                                        self_type: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)

    assert_equal Types::Union.new(types: [Types::Name.new_interface(name: :_A), Types::Name.new_interface(name: :_C)]),
                 construction.union_type(Types::Name.new_interface(name: :_A), Types::Name.new_interface(name: :_C))

    assert_equal Types::Name.new_interface(name: :_A),
                 construction.union_type(Types::Name.new_interface(name: :_A), Types::Name.new_interface(name: :_A))
  end

  def test_module_self
    source = parse_ruby(<<-EOF)
module Foo
  # @implements Foo<'a>
  
  block_given?
end
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker()

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        var_types: {},
                                        self_type: nil,
                                        block_context: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)

    construction.synthesize(source.node)

    assert_empty typing.errors
  end

  def test_class_constructor_with_signature
    source = parse_ruby("class Person; end")

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker(<<EOF)
class Person
end
EOF

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        var_types: {},
                                        self_type: nil,
                                        block_context: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)

    for_class = construction.for_class(source.node)

    assert_equal(
      Annotation::Implements::Module.new(
        name: Steep::ModuleName.parse("::Person"),
        args: []
      ),
      for_class.module_context.implement_name
    )
    assert_equal Types::Name.new_instance(name: "::Person"), for_class.module_context.instance_type
    assert_equal Types::Name.new_class(name: "::Person", constructor: nil), for_class.module_context.module_type
  end

  def test_class_constructor_without_signature
    source = parse_ruby("class Person; end")

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker(<<EOF)
class Address
end
EOF

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        var_types: {},
                                        self_type: nil,
                                        block_context: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)

    for_class = construction.for_class(source.node)

    assert_nil for_class.module_context.implement_name
    assert_nil for_class.module_context.instance_type
    assert_nil for_class.module_context.module_type
  end

  def test_class_constructor_nested
    source = parse_ruby("module Steep; class ModuleName; end; end")

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker(<<EOF)
class Steep::ModuleName
end
EOF

    module_context = TypeConstruction::ModuleContext.new(
      instance_type: Types::Name.new_instance(name: "::Steep"),
      module_type: Types::Name.new_module(name: "::Steep"),
      const_types: {},
      implement_name: nil,
      current_namespace: Steep::ModuleName.parse("::Steep"),
      const_env: nil
    )

    module_name_class_node = source.node.children[1]

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        var_types: {},
                                        self_type: nil,
                                        block_context: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: module_context,
                                        break_context: nil)

    for_module = construction.for_class(module_name_class_node)

    assert_equal(
      Annotation::Implements::Module.new(
        name: Steep::ModuleName.parse("::Steep::ModuleName"),
        args: []
      ),
      for_module.module_context.implement_name)
  end

  def test_module_constructor_with_signature
    source = parse_ruby("module Steep; end")

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker(<<EOF)
module Steep
end
EOF

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        var_types: {},
                                        self_type: nil,
                                        block_context: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)

    for_module = construction.for_module(source.node)

    assert_equal(
      Annotation::Implements::Module.new(
        name: Steep::ModuleName.parse("::Steep"),
        args: []
      ),
      for_module.module_context.implement_name
    )
    assert_equal Types::Name.new_instance(name: "::Steep"), for_module.module_context.instance_type
    assert_equal(
      Types::Intersection.new(
        types: [
          Types::Name.new_instance(name: "::Module"),
          Types::Name.new_module(name: "::Steep"),
        ]
      ),
      for_module.module_context.module_type
    )
  end

  def test_module_constructor_without_signature
    source = parse_ruby("module Steep; end")

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker(<<EOF)
module Rails
end
EOF

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        var_types: {},
                                        self_type: nil,
                                        block_context: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)

    for_module = construction.for_module(source.node)

    assert_nil for_module.module_context.implement_name
    assert_nil for_module.module_context.instance_type
    assert_equal Types::Name.new_instance(name: "::Module"), for_module.module_context.module_type
  end

  def test_module_constructor_nested
    source = parse_ruby("class Steep; module Printable; end; end")

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker(<<EOF)
module Steep::Printable
end
EOF

    module_context = TypeConstruction::ModuleContext.new(
      instance_type: Types::Name.new_instance(name: "::Steep"),
      module_type: Types::Name.new_class(name: "::Steep", constructor: false),
      const_types: {},
      implement_name: nil,
      current_namespace: Steep::ModuleName.parse("::Steep"),
      const_env: nil
    )

    module_node = source.node.children.last

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        var_types: {},
                                        self_type: nil,
                                        block_context: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: module_context,
                                        break_context: nil)

    for_module = construction.for_module(module_node)

    assert_equal(
      Annotation::Implements::Module.new(
        name: Steep::ModuleName.parse("::Steep::Printable"),
        args: []
      ),
      for_module.module_context.implement_name)
  end

  def test_new_method_constructor
    source = parse_ruby("class A; def foo(x); end; end")
    def_node = source.node.children[2]

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker(<<-EOF)
class A
  def foo: (String) -> Integer
end
    EOF

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        var_types: {},
                                        self_type: nil,
                                        block_context: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)

    for_method = construction.for_new_method(:foo,
                                             def_node,
                                             args: def_node.children[1].children,
                                             self_type: Types::Name.new_instance(name: "::A"))

    method_context = for_method.method_context
    assert_equal :foo, method_context.name
    assert_equal :foo, method_context.method.name
    assert_equal "(String) -> Integer", method_context.method_type.location.source
    assert_equal Types::Name.new_instance(name: "::Integer"), method_context.return_type
    refute method_context.constructor

    assert_equal Types::Name.new_instance(name: "::A"), for_method.self_type
    assert_nil for_method.block_context
    assert_equal [:x], for_method.var_types.keys.map(&:name)
    assert_equal Types::Name.new_instance(name: "::String"),
                 for_method.var_types.find {|name, _| name.name == :x }.last
  end

  def test_new_method_constructor_union
    source = parse_ruby("class A; def foo(x, **y); end; end")
    def_node = source.node.children[2]

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker(<<-EOF)
class A
  def foo: (String) -> Integer
         | (Object) -> Integer
end
    EOF

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        var_types: {},
                                        self_type: nil,
                                        block_context: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)

    for_method = construction.for_new_method(:foo,
                                             def_node,
                                             args: def_node.children[1].children,
                                             self_type: Types::Name.new_instance(name: "::A"))

    method_context = for_method.method_context
    assert_equal :foo, method_context.name
    assert_equal :foo, method_context.method.name
    assert_nil method_context.method_type
    assert_equal Types::Name.new_instance(name: "::Integer"), method_context.return_type
    refute method_context.constructor

    assert_equal Types::Name.new_instance(name: "::A"), for_method.self_type
    assert_nil for_method.block_context
    assert_empty for_method.var_types

    assert_equal 1, typing.errors.size
    assert_instance_of Steep::Errors::MethodDefinitionWithOverloading, typing.errors.first
  end

  def test_new_method_constructor_with_return_type
    source = parse_ruby(<<-RUBY)
class A
  def foo(x)
    # @type return: ::String
  end
end
RUBY
    def_node = source.node.children[2]

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker(<<-EOF)
class A
  def foo: (String) -> Integer
end
    EOF

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        var_types: {},
                                        self_type: nil,
                                        block_context: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)

    for_method = construction.for_new_method(:foo,
                                             def_node,
                                             args: def_node.children[1].children,
                                             self_type: Types::Name.new_instance(name: "::A"))

    method_context = for_method.method_context
    assert_equal :foo, method_context.name
    assert_equal :foo, method_context.method.name
    assert_equal "(String) -> Integer", method_context.method_type.location.source
    assert_equal Types::Name.new_instance(name: "::String"), method_context.return_type
    refute method_context.constructor

    assert_equal Types::Name.new_instance(name: "::A"), for_method.self_type
    assert_nil for_method.block_context
    assert_equal [:x], for_method.var_types.keys.map(&:name)
    assert_equal Types::Name.new_instance(name: "::String"), for_method.var_types.find {|name, _| name.name == :x }.last

    assert_equal 1, typing.errors.size
    assert_instance_of Steep::Errors::MethodReturnTypeAnnotationMismatch, typing.errors.first
  end

  def test_new_method_with_incompatible_annotation
    source = parse_ruby(<<-RUBY)
class A
  # @type method foo: (String) -> String
  def foo(x)
    nil
  end
end
    RUBY
    def_node = source.node.children[2]

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker(<<-EOF)
class A
  def foo: (String) -> Integer
end
    EOF

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        var_types: {},
                                        self_type: nil,
                                        block_context: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)

    for_method = construction.for_new_method(:foo,
                                             def_node,
                                             args: def_node.children[1].children,
                                             self_type: Types::Name.new_instance(name: "::A"))

    assert_equal 1, typing.errors.size
    assert_instance_of Steep::Errors::IncompatibleMethodTypeAnnotation, typing.errors.first
  end

  def test_relative_type_name
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

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker(<<-EOF)
class A::String
  def aaaaa: -> any
end
    EOF

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        var_types: {},
                                        self_type: nil,
                                        block_context: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)

    construction.synthesize(source.node)

    assert_equal 2, typing.errors.size

    assert_any typing.errors do |error| error.is_a?(Steep::Errors::IncompatibleAssignment) end
    typing.errors.find {|e| e.is_a?(Steep::Errors::IncompatibleAssignment) }.yield_self do |error|
      assert_equal Types::Name.new_instance(name: "::String"), error.rhs_type
      assert_equal Types::Name.new_instance(name: "::A::String"), error.lhs_type
    end

    assert_any typing.errors do |error| error.is_a?(Steep::Errors::MethodBodyTypeMismatch) end
    typing.errors.find {|e| e.is_a?(Steep::Errors::MethodBodyTypeMismatch) }.yield_self do |error|
      assert_equal Types::Name.new_instance(name: "::String"), error.actual
      assert_equal Types::Name.new_instance(name: "::A::String"), error.expected
    end
  end

  def test_namespace_module
    source = parse_ruby(<<-RUBY)
class A < Object
  class String
  end

  class XYZ
  end
end
    RUBY

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker(<<-EOF)
class A
  def foobar: -> any
end

class A::String
  def aaaaa: -> any
end
    EOF

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        var_types: {},
                                        self_type: nil,
                                        block_context: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)

    construction.synthesize(source.node)

    assert_equal 1, typing.errors.size
    assert_instance_of Steep::Errors::MethodDefinitionMissing, typing.errors[0]
  end

  def test_namespace_module_nested
    source = parse_ruby(<<-RUBY)
class A::String < Object
  def foo
    # @type var x: String
    x = ""
  end
end
    RUBY

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker(<<-EOF)
class A
end

class A::String
  def foo: -> any
end
    EOF

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        var_types: {},
                                        self_type: nil,
                                        block_context: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)

    construction.synthesize(source.node)

    assert_empty typing.errors
  end

  def test_namespace_module_nested2
    source = parse_ruby(<<-RUBY)
class ::A::String < Object
  def foo
    # @type var x: String
    x = ""
  end
end
    RUBY

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker(<<-EOF)
class A
end

class A::String
  def foo: -> any
end
    EOF

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        var_types: {},
                                        self_type: nil,
                                        block_context: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)

    construction.synthesize(source.node)

    assert_empty typing.errors
  end

  def test_masgn
    source = parse_ruby(<<-EOF)
# @type var a: String
# @type ivar @b: String
a, @b = 1, 2
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker()

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        ivar_types: annotations.ivar_types,
                                        var_types: {},
                                        self_type: nil,
                                        block_context: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)

    construction.synthesize(source.node)

    assert_equal 2, typing.errors.size
    assert_any typing.errors do |error|
      error.is_a?(Steep::Errors::IncompatibleAssignment) &&
        error.node.type == :lvasgn
    end
    assert_any typing.errors do |error|
      error.is_a?(Steep::Errors::IncompatibleAssignment) &&
        error.node.type == :ivasgn
    end
  end

  def test_masgn_array
    source = parse_ruby(<<-EOF)
# @type var a: String
# @type ivar @b: String
x = [1, 2]
a, @b = x
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker()

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        ivar_types: annotations.ivar_types,
                                        var_types: {},
                                        self_type: nil,
                                        block_context: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)

    construction.synthesize(source.node)

    assert_equal 2, typing.errors.size
    assert_any typing.errors do |error|
      error.is_a?(Steep::Errors::IncompatibleAssignment) &&
        error.node.type == :lvasgn
    end
    assert_any typing.errors do |error|
      error.is_a?(Steep::Errors::IncompatibleAssignment) &&
        error.node.type == :ivasgn
    end
  end

  def test_masgn_array_error
    source = parse_ruby(<<-EOF)
a, @b = 3
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker()

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        ivar_types: annotations.ivar_types,
                                        var_types: {},
                                        self_type: nil,
                                        block_context: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)

    construction.synthesize(source.node)

    assert_equal 1, typing.errors.size
    assert_any typing.errors do |error|
      error.is_a?(Steep::Errors::FallbackAny)
    end
  end

  def test_op_asgn
    source = parse_ruby(<<-EOF)
# @type var a: String
a = ""
a += ""
a += 3
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker()

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        ivar_types: annotations.ivar_types,
                                        var_types: {},
                                        self_type: nil,
                                        block_context: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)

    construction.synthesize(source.node)

    assert_equal 1, typing.errors.size
    assert_any typing.errors do |error|
      error.is_a?(Steep::Errors::ArgumentTypeMismatch)
    end
  end

  def test_while
    source = parse_ruby(<<-EOF)
while true
  break
end
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker()

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        ivar_types: annotations.ivar_types,
                                        var_types: {},
                                        self_type: nil,
                                        block_context: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)

    construction.synthesize(source.node)

    assert_empty typing.errors
  end

  def test_while2
    source = parse_ruby(<<-EOF)
tap do
  while true
    break 30
  end
end
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker()

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        ivar_types: annotations.ivar_types,
                                        var_types: {},
                                        self_type: Types::Name.new_instance(name: "::Object"),
                                        block_context: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)

    construction.synthesize(source.node)

    assert_equal 1, typing.errors.size
    assert_any typing.errors do |error|
      error.is_a?(Steep::Errors::UnexpectedJumpValue)
    end
  end

  def test_while3
    source = parse_ruby(<<-EOF)
while true
  tap do
    break self
  end
end
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker()

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        ivar_types: annotations.ivar_types,
                                        var_types: {},
                                        self_type: Types::Name.new_instance(name: "::Object"),
                                        block_context: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)

    construction.synthesize(source.node)

    assert_empty typing.errors
  end

  def test_while_post
    source = parse_ruby(<<-EOF)
begin
  a = 3
end while true
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker()

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        ivar_types: annotations.ivar_types,
                                        var_types: {},
                                        self_type: Types::Name.new_instance(name: "::Object"),
                                        block_context: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)

    construction.synthesize(source.node)

    assert_empty typing.errors
  end

  def test_range
    source = parse_ruby(<<-EOF)
# @type var a: Range<Integer>
a = 1..2
a = 2..."a"
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker()

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        ivar_types: annotations.ivar_types,
                                        var_types: {},
                                        self_type: Types::Name.new_instance(name: "::Object"),
                                        block_context: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)

    construction.synthesize(source.node)

    assert_equal 1, typing.errors.size
    assert_any typing.errors do |error|
      error.is_a?(Steep::Errors::IncompatibleAssignment)
    end
  end

  def test_regexp
    source = parse_ruby(<<-'EOF')
# @type var a: Regexp
a = /./
a = /#{a + 3}/
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker()

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        ivar_types: annotations.ivar_types,
                                        var_types: {},
                                        self_type: Types::Name.new_instance(name: "::Object"),
                                        block_context: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)

    construction.synthesize(source.node)

    assert_equal 1, typing.errors.size
    assert_any typing.errors do |error|
      error.is_a?(Steep::Errors::NoMethod)
    end
  end

  def test_nth_ref
    source = parse_ruby(<<-'EOF')
# @type var a: Integer
a = $1
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker()

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        ivar_types: annotations.ivar_types,
                                        var_types: {},
                                        self_type: Types::Name.new_instance(name: "::Object"),
                                        block_context: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)

    construction.synthesize(source.node)

    assert_equal 1, typing.errors.size
    assert_any typing.errors do |error|
      error.is_a?(Steep::Errors::IncompatibleAssignment)
    end
  end

  def test_or_and_asgn
    source = parse_ruby(<<-'EOF')
a = 3
a &&= a
a ||= a + "foo"
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker()

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        ivar_types: annotations.ivar_types,
                                        var_types: {},
                                        self_type: Types::Name.new_instance(name: "::Object"),
                                        block_context: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)

    construction.synthesize(source.node)

    assert_equal 1, typing.errors.size
    assert_any typing.errors do |error|
      error.is_a?(Steep::Errors::NoMethod)
    end
  end

  def test_next
    source = parse_ruby(<<-'EOF')
while true
  next
end
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker()

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        ivar_types: annotations.ivar_types,
                                        var_types: {},
                                        self_type: Types::Name.new_instance(name: "::Object"),
                                        block_context: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)

    construction.synthesize(source.node)

    assert_empty typing.errors
  end

  def test_next1
    source = parse_ruby(<<-'EOF')
while true
  next 3
end
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker()

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        ivar_types: annotations.ivar_types,
                                        var_types: {},
                                        self_type: Types::Name.new_instance(name: "::Object"),
                                        block_context: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)

    construction.synthesize(source.node)

    refute_empty typing.errors
    assert_any typing.errors do |error|
      error.is_a?(Steep::Errors::UnexpectedJumpValue)
    end
  end

  def test_next2
    source = parse_ruby(<<-'EOF')
tap do |a|
  next
end
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker()

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        ivar_types: annotations.ivar_types,
                                        var_types: {},
                                        self_type: Types::Name.new_instance(name: "::Object"),
                                        block_context: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)

    construction.synthesize(source.node)

    assert_empty typing.errors
  end

  def test_method_arg_assign
    source = parse_ruby(<<-'EOF')
def f(x)
  x = "forever" if x == nil
end
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker()

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        ivar_types: annotations.ivar_types,
                                        var_types: {},
                                        self_type: Types::Name.new_instance(name: "::Object"),
                                        block_context: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)

    construction.synthesize(source.node)
  end

  def test_restargs
    source = parse_ruby(<<-'EOF')
def f(*x)
  # @type var y: String
  y = x
end
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker()

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        ivar_types: annotations.ivar_types,
                                        var_types: {},
                                        self_type: Types::Name.new_instance(name: "::Object"),
                                        block_context: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)

    construction.synthesize(source.node)

    assert_equal 2, typing.errors.size
    assert_any typing.errors do |error| error.is_a?(Steep::Errors::FallbackAny) end
    assert_any typing.errors do |error| error.is_a?(Steep::Errors::IncompatibleAssignment) end
  end

  def test_restargs2
    source = parse_ruby(<<-'EOF')
# @type method f: (*String) -> any
def f(*x)
  # @type var y: String
  y = x
end
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker()

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        ivar_types: annotations.ivar_types,
                                        var_types: {},
                                        self_type: Types::Name.new_instance(name: "::Object"),
                                        block_context: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)

    construction.synthesize(source.node)

    assert_equal 1, typing.errors.size
    assert_any typing.errors do |error| error.is_a?(Steep::Errors::IncompatibleAssignment) end
  end

  def test_gvar
    source = parse_ruby(<<-'EOF')
$HOGE = 3
x = $HOGE
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker(<<-EOF)
$HOGE: Integer
    EOF

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        ivar_types: annotations.ivar_types,
                                        var_types: {},
                                        self_type: Types::Name.new_instance(name: "::Object"),
                                        block_context: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)

    construction.synthesize(source.node)

    assert_empty typing.errors
  end

  def test_gvar1
    source = parse_ruby(<<-'EOF')
$HOGE = ""

# @type var x: Array<String>
x = $HOGE
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker(<<-EOF)
$HOGE: Integer
    EOF

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        ivar_types: annotations.ivar_types,
                                        var_types: {},
                                        self_type: Types::Name.new_instance(name: "::Object"),
                                        block_context: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)

    construction.synthesize(source.node)

    assert_equal 2, typing.errors.size
    assert typing.errors.all? {|error| error.is_a?(Steep::Errors::IncompatibleAssignment) }
  end

  def test_gvar2
    source = parse_ruby(<<-'EOF')
$HOGE = 3
x = $HOGE
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker()

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        ivar_types: annotations.ivar_types,
                                        var_types: {},
                                        self_type: Types::Name.new_instance(name: "::Object"),
                                        block_context: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)

    construction.synthesize(source.node)

    assert_equal 2, typing.errors.size
    assert typing.errors.all? {|error| error.is_a?(Steep::Errors::FallbackAny) }
  end

  def test_ivar
    source = parse_ruby(<<-'EOF')
class A
  def foo
    @foo
  end
end
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker(<<-EOF)
class A
  def foo: -> String
  @foo: String
end
    EOF

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        ivar_types: annotations.ivar_types,
                                        var_types: {},
                                        self_type: Types::Name.new_instance(name: "::Object"),
                                        block_context: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)

    construction.synthesize(source.node)

    assert_empty typing.errors
  end

  def test_ivar2
    source = parse_ruby(<<-'EOF')
class A
  x = @foo
end
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker(<<-EOF)
class A
  @foo: String
end
    EOF

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        ivar_types: annotations.ivar_types,
                                        var_types: {},
                                        self_type: Types::Name.new_instance(name: "::Object"),
                                        block_context: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)

    construction.synthesize(source.node)

    assert_equal 1, typing.errors.size
    assert_any typing.errors do |error| error.is_a?(Steep::Errors::FallbackAny) end
  end

  def test_splat
    source = parse_ruby(<<-'EOF')
a = [1]

# @type var b: Array<String>
b = [*a]
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker()

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        ivar_types: annotations.ivar_types,
                                        var_types: {},
                                        self_type: Types::Name.new_instance(name: "::Object"),
                                        block_context: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)

    construction.synthesize(source.node)

    assert_equal 1, typing.errors.size
    assert_any typing.errors do |error|
      error.is_a?(Steep::Errors::IncompatibleAssignment)
    end
  end

  def test_splat_range
    source = parse_ruby(<<-'EOF')
# @type var b: Array<String>
b = [*1...3]
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker()

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        ivar_types: annotations.ivar_types,
                                        var_types: {},
                                        self_type: Types::Name.new_instance(name: "::Object"),
                                        block_context: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)

    construction.synthesize(source.node)

    assert_equal 1, typing.errors.size
    assert_any typing.errors do |error|
      error.is_a?(Steep::Errors::IncompatibleAssignment)
    end
  end

  def test_splat_error
    source = parse_ruby(<<-'EOF')
a = 1
b = [*a]
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker()

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        ivar_types: annotations.ivar_types,
                                        var_types: {},
                                        self_type: Types::Name.new_instance(name: "::Object"),
                                        block_context: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)

    construction.synthesize(source.node)

    assert_equal 1, typing.errors.size
    assert_any typing.errors do |error|
      error.is_a?(Steep::Errors::FallbackAny)
    end
  end

  def test_splat_arg
    source = parse_ruby(<<-'EOF')
a = A.new
a.gen(*["1"])
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker(<<-EOF)
class A
  def initialize: () -> any
  def gen: (*Integer) -> String
end
    EOF

    env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    module_context = TypeConstruction::ModuleContext.new(
      instance_type: nil,
      module_type: nil,
      const_types: annotations.const_types,
      implement_name: nil,
      current_namespace: nil,
      const_env: env
    )

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        ivar_types: annotations.ivar_types,
                                        var_types: {},
                                        self_type: Types::Name.new_instance(name: "::Object"),
                                        block_context: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: module_context,
                                        break_context: nil)

    construction.synthesize(source.node)

    assert_equal 1, typing.errors.size
    assert_any typing.errors do |error|
      error.is_a?(Steep::Errors::ArgumentTypeMismatch)
    end
  end

  def test_void
    source = parse_ruby(<<-'EOF')
class Hoge
  def foo(a)
    # @type var x: Integer
    x = a.foo(self)
    a.foo(self).class
  end
end
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker(<<-EOF)
class Hoge
  def foo: (self) -> void
end
    EOF

    env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    module_context = TypeConstruction::ModuleContext.new(
      instance_type: nil,
      module_type: nil,
      const_types: annotations.const_types,
      implement_name: nil,
      current_namespace: nil,
      const_env: env
    )

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        ivar_types: annotations.ivar_types,
                                        var_types: {},
                                        self_type: Types::Name.new_instance(name: "::Object"),
                                        block_context: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: module_context,
                                        break_context: nil)

    construction.synthesize(source.node)

    assert_equal 2, typing.errors.size
    assert_any typing.errors do |error|
      error.is_a?(Steep::Errors::IncompatibleAssignment) && error.rhs_type.is_a?(Types::Void)
    end
    assert_any typing.errors do |error|
      error.is_a?(Steep::Errors::NoMethod) && error.type.is_a?(Types::Void)
    end
  end

  def test_void2
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

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = checker(<<-EOF)
class Hoge
  def foo: () { () -> void } -> any
end
    EOF

    env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    module_context = TypeConstruction::ModuleContext.new(
      instance_type: nil,
      module_type: nil,
      const_types: annotations.const_types,
      implement_name: nil,
      current_namespace: nil,
      const_env: env
    )

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        ivar_types: annotations.ivar_types,
                                        var_types: {},
                                        self_type: Types::Name.new_instance(name: "::Object"),
                                        block_context: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: module_context,
                                        break_context: nil)

    construction.synthesize(source.node)

    assert_equal 2, typing.errors.size
    assert_any typing.errors do |error|
      error.is_a?(Steep::Errors::IncompatibleAssignment) && error.rhs_type.is_a?(Types::Void)
    end
    assert_any typing.errors do |error|
      error.is_a?(Steep::Errors::NoMethod) && error.type.is_a?(Types::Void)
    end
  end
end
