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

module Foo
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
                                        module_context: nil)
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
                                        module_context: nil)
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
                                        module_context: nil)
    construction.synthesize(source.node)

    assert_equal Types::Name.new_instance(name: :Integer), typing.type_of(node: source.node)
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
                                        module_context: nil)
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
                                        module_context: nil)
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
                                        module_context: nil)
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
                                        module_context: nil)
    construction.synthesize(source.node)

    assert_equal Types::Any.new, typing.type_of(node: source.node)

    assert_equal 1, typing.errors.size
    assert_argument_type_mismatch typing.errors[0], type: Types::Name.new_interface(name: :_C), method: :g
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
                                        module_context: nil)
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
                                        module_context: nil)
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
                                        module_context: nil)
    construction.synthesize(source.node)

    assert_equal Types::Any.new, typing.type_of(node: source.node)

    assert_equal 1, typing.errors.size
    assert_argument_type_mismatch typing.errors[0], type: Types::Name.new_interface(name: :_C), method: :g
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
                                        module_context: nil)
    construction.synthesize(source.node)

    assert_equal Types::Any.new, typing.type_of(node: source.node)

    assert_equal 1, typing.errors.size
    assert_argument_type_mismatch typing.errors.first, type: Types::Name.new_interface(name: :_C), method: :g
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
                                        module_context: nil)
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
                                        module_context: nil)
    construction.synthesize(source.node)

    assert_equal Types::Any.new, typing.type_of(node: source.node)

    assert_equal 1, typing.errors.size
    assert_argument_type_mismatch typing.errors[0], type: Types::Name.new_interface(name: :_C), method: :h
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
                                        module_context: nil)
    construction.synthesize(source.node)

    assert_equal Types::Any.new, typing.type_of(node: source.node)

    assert_equal 1, typing.errors.size
    assert_argument_type_mismatch typing.errors[0], type: Types::Name.new_interface(name: :_C), method: :h
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
                                        module_context: nil)
    construction.synthesize(source.node)

    assert_equal Types::Any.new, typing.type_of(node: source.node)

    assert_equal 1, typing.errors.size
    assert_argument_type_mismatch typing.errors[0], type: Types::Name.new_interface(name: :_C), method: :h
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
                                        module_context: nil)
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
                                        module_context: nil)
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
                                        module_context: nil)
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
                                        module_context: nil)
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
                                        module_context: nil)
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
                                        module_context: nil)
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
                                        module_context: nil)
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
                                        module_context: nil)
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
                                        module_context: nil)
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
                                        module_context: nil)
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
                                        module_context: nil)
    construction.synthesize(source.node)

    assert_any typing.errors do |error|
      error.is_a?(Steep::Errors::ReturnTypeMismatch) && error.expected == Types::Name.new_interface(name: :_X) && error.actual == Types::Name.new_interface(name: :_A)
    end
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
                                        module_context: nil)
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
                                        module_context: nil)
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
    skip "Type variable propagation requires constraint solver!!!"

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
                                        module_context: nil)
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
                                        module_context: nil)
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
                                        module_context: nil)

    assert_equal Types::Union.new(types: [Types::Name.new_interface(name: :_A), Types::Name.new_interface(name: :_C)]),
                 construction.union_type(Types::Name.new_interface(name: :_A), Types::Name.new_interface(name: :_C))

    assert_equal Types::Name.new_interface(name: :_A),
                 construction.union_type(Types::Name.new_interface(name: :_A), Types::Name.new_interface(name: :_A))
  end

  def test_module_self
    source = parse_ruby(<<-EOF)
module Foo
  # @implements Foo
  
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
                                        module_context: nil)

    construction.synthesize(source.node)

    assert_empty typing.errors
  end
end
