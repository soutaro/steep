require "test_helper"

class TypeConstructionTest < Minitest::Test
  Source = Steep::Source
  TypeAssignability = Steep::TypeAssignability
  Typing = Steep::Typing
  TypeConstruction = Steep::TypeConstruction
  Parser = Steep::Parser
  Annotation = Steep::Annotation
  Types = Steep::Types
  Interface = Steep::Interface
  TypeName = Steep::TypeName

  include TestHelper
  include TypeErrorAssertions

  def ruby(string)
    Steep::Source.parse(string, path: Pathname("foo.rb"))
  end

  def assignability
    TypeAssignability.new do |assignability|
      interfaces = Parser.parse_signature(<<-EOS)
class BasicObject
end

class Object <: BasicObject
  def block_given?: -> any
end

class Class
end

class Module
end

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
      interfaces.each do |interface|
        assignability.add_signature interface
      end
    end
  end

  def test_lvar_with_annotation
    source = ruby(<<-EOF)
# @type var x: _A
x = nil
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)

    construction = TypeConstruction.new(assignability: assignability,
                                        source: source,
                                        annotations: annotations,
                                        var_types: {},
                                        self_type: nil,
                                        block_context: nil,
                                        typing: typing,
                                        method_context: nil,
                                        module_context: nil)
    construction.synthesize(source.node)

    assert_equal Types::Name.interface(name: :_A), typing.type_of(node: source.node)
    assert_empty typing.errors
  end

  def test_lvar_with_annotation_type_check
    source = ruby(<<-EOF)
# @type var x: _B
# @type var z: _A
x = nil
z = x
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)

    construction = TypeConstruction.new(assignability: assignability,
                                        source: source,
                                        annotations: annotations,
                                        var_types: {},
                                        self_type: nil,
                                        typing: typing,
                                        block_context: nil,
                                        method_context: nil,
                                        module_context: nil)
    construction.synthesize(source.node)

    assert_equal Types::Name.interface(name: :_A), typing.type_of(node: source.node)

    assert_equal 1, typing.errors.size
    assert_incompatible_assignment typing.errors[0],
                                   lhs_type: Types::Name.interface(name: :_A),
                                   rhs_type: Types::Name.interface(name: :_B) do |error|
      assert_equal :lvasgn, error.node.type
      assert_equal :z, error.node.children[0].name
    end
  end

  def test_lvar_without_annotation
    source = ruby(<<-EOF)
x = 1
z = x
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)

    construction = TypeConstruction.new(assignability: assignability,
                                        source: source,
                                        annotations: annotations,
                                        var_types: {},
                                        block_context: nil,
                                        self_type: nil,
                                        typing: typing,
                                        method_context: nil,
                                        module_context: nil)
    construction.synthesize(source.node)

    assert_equal Types::Name.instance(name: :Integer), typing.type_of(node: source.node)
    assert_empty typing.errors
  end

  def test_lvar_without_annotation_inference
    source = ruby(<<-EOF)
# @type var x: _A
x = nil
z = x
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)

    construction = TypeConstruction.new(assignability: assignability,
                                        source: source,
                                        annotations: annotations,
                                        var_types: {},
                                        block_context: nil,
                                        self_type: nil,
                                        typing: typing,
                                        method_context: nil,
                                        module_context: nil)
    construction.synthesize(source.node)

    assert_equal Types::Name.interface(name: :_A), typing.type_of(node: source.node)
    assert_empty typing.errors
  end

  def test_method_call
    source = ruby(<<-EOF)
# @type var x: _C
x = nil
x.f
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)

    construction = TypeConstruction.new(assignability: assignability,
                                        source: source,
                                        annotations: annotations,
                                        var_types: {},
                                        block_context: nil,
                                        self_type: nil,
                                        typing: typing,
                                        method_context: nil,
                                        module_context: nil)
    construction.synthesize(source.node)

    assert_equal Types::Name.interface(name: :_A), typing.type_of(node: source.node)
    assert_empty typing.errors
  end

  def test_method_call_with_argument
    source = ruby(<<-EOF)
# @type var x: _C
# @type var y: _A
x = nil
y = nil
x.g(y)
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)

    construction = TypeConstruction.new(assignability: assignability,
                                        source: source,
                                        annotations: annotations,
                                        var_types: {},
                                        block_context: nil,
                                        self_type: nil,
                                        typing: typing,
                                        method_context: nil,
                                        module_context: nil)
    construction.synthesize(source.node)

    assert_equal Types::Name.interface(name: :_B), typing.type_of(node: source.node)
    assert_empty typing.errors
  end

  def test_method_call_incompatible_argument_type
    source = ruby(<<-EOF)
# @type var x: _C
# @type var y: _B
x = nil
y = nil
x.g(y)
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)

    construction = TypeConstruction.new(assignability: assignability,
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
    assert_argument_type_mismatch typing.errors[0], type: Types::Name.interface(name: :_C), method: :g
  end

  def test_method_call_no_error_if_any
    source = ruby(<<-EOF)
x = nil
x.no_such_method
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)

    construction = TypeConstruction.new(assignability: assignability,
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
    source = ruby(<<-EOF)
# @type var x: _C
x = nil
x.no_such_method
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)

    construction = TypeConstruction.new(assignability: assignability,
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
    assert_no_method_error typing.errors.first, method: :no_such_method, type: Types::Name.interface(name: :_C)
  end

  def test_method_call_missing_argument
    source = ruby(<<-EOF)
# @type var x: _A
# @type var a: _C
a = nil
x = nil
a.g()
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)

    construction = TypeConstruction.new(assignability: assignability,
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
    assert_argument_type_mismatch typing.errors[0], type: Types::Name.interface(name: :_C), method: :g
  end

  def test_method_call_extra_args
    source = ruby(<<-EOF)
# @type var x: _A
# @type var a: _C
a = nil
x = nil
a.g(nil, nil, nil)
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)

    construction = TypeConstruction.new(assignability: assignability,
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
    assert_argument_type_mismatch typing.errors.first, type: Types::Name.interface(name: :_C), method: :g
  end

  def test_keyword_call
    source = ruby(<<-EOF)
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

    construction = TypeConstruction.new(assignability: assignability,
                                        source: source,
                                        annotations: annotations,
                                        var_types: {},
                                        block_context: nil,
                                        self_type: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil)
    construction.synthesize(source.node)

    assert_equal Types::Name.interface(name: :_C), typing.type_of(node: source.node)
    assert_empty typing.errors
  end

  def test_keyword_missing
    source = ruby(<<-EOF)
# @type var x: _C
x = nil
x.h()
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)

    construction = TypeConstruction.new(assignability: assignability,
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
    assert_argument_type_mismatch typing.errors[0], type: Types::Name.interface(name: :_C), method: :h
  end

  def test_extra_keyword_given
    source = ruby(<<-EOF)
# @type var x: _C
x = nil
x.h(a: nil, b: nil, c: nil)
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)

    construction = TypeConstruction.new(assignability: assignability,
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
    assert_argument_type_mismatch typing.errors[0], type: Types::Name.interface(name: :_C), method: :h
  end

  def test_keyword_typecheck
    source = ruby(<<-EOF)
# @type var x: _C
# @type var y: _B
x = nil
y = nil
x.h(a: y)
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)

    construction = TypeConstruction.new(assignability: assignability,
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
    assert_argument_type_mismatch typing.errors[0], type: Types::Name.interface(name: :_C), method: :h
  end

  def test_def_no_params
    source = ruby(<<-EOF)
def foo
  # @type var x: _A
  x = nil
end
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)

    construction = TypeConstruction.new(assignability: assignability,
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
    assert_equal Types::Name.interface(name: :_A), typing.type_of(node: def_body)
  end

  def test_def_param
    source = ruby(<<-EOF)
def foo(x)
  # @type var x: _A
  y = x
end
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)

    construction = TypeConstruction.new(assignability: assignability,
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
    assert_equal Types::Name.interface(name: :_A), typing.type_of(node: def_body)
    assert_equal Types::Name.interface(name: :_A), typing.type_of_variable(name: :x)
    assert_equal Types::Name.interface(name: :_A), typing.type_of_variable(name: :y)
  end

  def test_def_param_error
    source = ruby(<<-EOF)
def foo(x, y = x)
  # @type var x: _A
  # @type var y: _C
end
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)

    construction = TypeConstruction.new(assignability: assignability,
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
                                   lhs_type: Types::Name.interface(name: :_C),
                                   rhs_type: Types::Name.interface(name: :_A) do |error|
      assert_equal :optarg, error.node.type
      assert_equal :y, error.node.children[0].name
    end

    assert_equal Types::Name.interface(name: :_A), typing.type_of_variable(name: :x)
    assert_equal Types::Name.interface(name: :_C), typing.type_of_variable(name: :y)
  end

  def test_def_kw_param_error
    source = ruby(<<-EOF)
def foo(x:, y: x)
  # @type var x: _A
  # @type var y: _C
end
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)

    construction = TypeConstruction.new(assignability: assignability,
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
                                   lhs_type: Types::Name.interface(name: :_C),
                                   rhs_type: Types::Name.interface(name: :_A) do |error|
      assert_equal :kwoptarg, error.node.type
      assert_equal :y, error.node.children[0].name
    end

    assert_equal Types::Name.interface(name: :_A), typing.type_of_variable(name: :x)
    assert_equal Types::Name.interface(name: :_C), typing.type_of_variable(name: :y)
  end

  def test_block
    source = ruby(<<-EOF)
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

    construction = TypeConstruction.new(assignability: assignability,
                                        source: source,
                                        annotations: annotations,
                                        var_types: {},
                                        block_context: nil,
                                        self_type: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil)
    construction.synthesize(source.node)

    assert_equal Types::Name.interface(name: :_X), typing.type_of_variable(name: :a)
    assert_equal Types::Name.interface(name: :_C), typing.type_of_variable(name: :b)
    assert_equal Types::Name.interface(name: :_A), typing.type_of_variable(name: :x)
    assert_equal Types::Name.interface(name: :_B), typing.type_of_variable(name: :y)
  end

  def test_block_shadow
    source = ruby(<<-EOF)
# @type var a: _X
a = nil

a.f do |a|
  # @type var a: _A
  b = a
end
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)

    construction = TypeConstruction.new(assignability: assignability,
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
    assert_equal Types::Name.interface(name: :_A), typing.type_of_variable(name: :b)
  end

  def test_block_param_type
    source = ruby(<<-EOF)
# @type var x: _X
x = nil

x.f do |a|
  # @type var d: _D
  d = nil
end
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)

    construction = TypeConstruction.new(assignability: assignability,
                                        source: source,
                                        annotations: annotations,
                                        var_types: {},
                                        block_context: nil,
                                        self_type: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil)
    construction.synthesize(source.node)

    assert_equal Types::Name.interface(name: :_X), typing.type_of_variable(name: :x)
    assert_equal Types::Name.interface(name: :_A), typing.type_of_variable(name: :a)
    assert_equal Types::Name.interface(name: :_D), typing.type_of_variable(name: :d)
    assert_empty typing.errors
  end

  def test_block_value_type
    source = ruby(<<-EOF)
# @type var x: _X
x = nil

x.f do |a|
  a
end
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)

    construction = TypeConstruction.new(assignability: assignability,
                                        source: source,
                                        annotations: annotations,
                                        var_types: {},
                                        block_context: nil,
                                        self_type: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil)
    construction.synthesize(source.node)

    assert_equal Types::Name.interface(name: :_X), typing.type_of_variable(name: :x)
    assert_equal Types::Name.interface(name: :_A), typing.type_of_variable(name: :a)

    assert_equal 1, typing.errors.size
    assert_block_type_mismatch typing.errors[0], expected: Types::Name.interface(name: :_D), actual: Types::Name.interface(name: :_A)
  end

  def test_block_break_type
    source = ruby(<<-EOF)
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

    construction = TypeConstruction.new(assignability: assignability,
                                        source: source,
                                        annotations: annotations,
                                        var_types: {},
                                        block_context: nil,
                                        self_type: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil)
    construction.synthesize(source.node)

    assert_equal Types::Name.interface(name: :_X), typing.type_of_variable(name: :x)
    assert_equal Types::Name.interface(name: :_A), typing.type_of_variable(name: :a)

    assert_equal 1, typing.errors.size
    assert_break_type_mismatch typing.errors[0], expected: Types::Name.interface(name: :_C), actual: Types::Name.interface(name: :_A)
  end

  def test_return_type
    source = ruby(<<-EOF)
def foo()
  # @type return: _A
  # @type var a: _A
  a = nil
  return a
end
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)

    construction = TypeConstruction.new(assignability: assignability,
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
    source = ruby(<<-EOF)
def foo()
  # @type return: _X
  # @type var a: _A
  a = nil
  return a
end
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)

    construction = TypeConstruction.new(assignability: assignability,
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
      error.is_a?(Steep::Errors::ReturnTypeMismatch) && error.expected == Types::Name.interface(name: :_X) && error.actual == Types::Name.interface(name: :_A)
    end
  end

  def test_union_method
    source = ruby(<<-EOF)
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

    construction = TypeConstruction.new(assignability: assignability,
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
    source = ruby(<<-EOF)
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

    construction = TypeConstruction.new(assignability: assignability,
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
    source = ruby(<<-EOF)
# @type var poly: _PolyMethod
poly = nil

# @type var string: String
string = poly.snd(1, "a")
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)

    construction = TypeConstruction.new(assignability: assignability,
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
    source = ruby(<<-EOF)
# @type var poly: _PolyMethod
poly = nil

# @type var string: String
string = poly.try { "string" }
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)

    construction = TypeConstruction.new(assignability: assignability,
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

  def arguments(ruby)
    ::Parser::CurrentRuby.parse(ruby).children.drop(2)
  end

  def parameters(ruby)
    ASTUtils::Labeling.translate(node: ::Parser::CurrentRuby.parse(ruby)).children[1].children
  end

  def test_argument_pairs
    params = Interface::Params.empty.with(required: [Types::Name.interface(name: :_A)],
                                          optional: [Types::Name.interface(name: :_B)],
                                          rest: Types::Name.interface(name: :_C),
                                          required_keywords: { d: Types::Name.interface(name: :_D) },
                                          optional_keywords: { e: Types::Name.interface(name: :_E) },
                                          rest_keywords: Types::Name.interface(name: :_F))
    arguments = arguments("f(a, b, c, d: d, e: e, f: f)")

    assert_equal [
                   [Types::Name.interface(name: :_A), arguments[0]],
                   [Types::Name.interface(name: :_B), arguments[1]],
                   [Types::Name.interface(name: :_C), arguments[2]],
                   [Types::Name.interface(name: :_D), arguments[3].children[0].children[1]],
                   [Types::Name.interface(name: :_E), arguments[3].children[1].children[1]],
                   [Types::Name.interface(name: :_F), arguments[3].children[2].children[1]]
                 ], TypeConstruction.argument_typing_pairs(params: params, arguments: arguments)
  end

  def test_argument_pairs_rest_keywords
    params = Interface::Params.empty.with(required: [Types::Name.interface(name: :_A)],
                                          optional: [Types::Name.interface(name: :_B)],
                                          rest: Types::Name.interface(name: :_C),
                                          required_keywords: { d: Types::Name.interface(name: :_D) },
                                          optional_keywords: { e: Types::Name.interface(name: :_E) },
                                          rest_keywords: Types::Name.interface(name: :_F))
    arguments = arguments("f(a, b, c, d: d, e: e, f: f)")

    assert_equal [
                   [Types::Name.interface(name: :_A), arguments[0]],
                   [Types::Name.interface(name: :_B), arguments[1]],
                   [Types::Name.interface(name: :_C), arguments[2]],
                   [Types::Name.interface(name: :_D), arguments[3].children[0].children[1]],
                   [Types::Name.interface(name: :_E), arguments[3].children[1].children[1]],
                   [Types::Name.interface(name: :_F), arguments[3].children[2].children[1]]
                 ], TypeConstruction.argument_typing_pairs(params: params, arguments: arguments)
  end

  def test_argument_pairs_required
    params = Interface::Params.empty.with(required: [Types::Name.interface(name: :_A)],
                                          optional: [Types::Name.interface(name: :_B)],
                                          rest: Types::Name.interface(name: :_C))
    arguments = arguments("f(a, b, c)")

    assert_equal [
                   [Types::Name.interface(name: :_A), arguments[0]],
                   [Types::Name.interface(name: :_B), arguments[1]],
                   [Types::Name.interface(name: :_C), arguments[2]],
                 ], TypeConstruction.argument_typing_pairs(params: params, arguments: arguments)
  end

  def test_argument_pairs_hash
    params = Interface::Params.empty.with(required: [Types::Name.interface(name: :_A)],
                                          optional: [Types::Name.interface(name: :_B)],
                                          rest: Types::Name.interface(name: :_C))
    arguments = arguments("f(a, b, c, d: d)")

    assert_equal [
                   [Types::Name.interface(name: :_A), arguments[0]],
                   [Types::Name.interface(name: :_B), arguments[1]],
                   [Types::Name.interface(name: :_C), arguments[2]],
                   [Types::Name.interface(name: :_C), arguments[3]]
                 ], TypeConstruction.argument_typing_pairs(params: params, arguments: arguments)
  end

  def test_argument_keywords
    params = Interface::Params.empty.with(required_keywords: { d: Types::Name.interface(name: :_D) },
                                          optional_keywords: { e: Types::Name.interface(name: :_E) },
                                          rest_keywords: Types::Name.interface(name: :_F))

    arguments = arguments("f(d: d, e: e, f: f)")

    assert_equal [
                   [Types::Name.interface(name: :_D), arguments[0].children[0].children[1]],
                   [Types::Name.interface(name: :_E), arguments[0].children[1].children[1]],
                   [Types::Name.interface(name: :_F), arguments[0].children[2].children[1]],
                 ], TypeConstruction.argument_typing_pairs(params: params, arguments: arguments)
  end

  def test_argument_hash_not_keywords
    params = Interface::Params.empty.with(required: [Types::Name.interface(name: :_A)])

    arguments = arguments("f(d: d, e: e, f: f)")

    assert_equal [
                   [Types::Name.interface(name: :_A), arguments[0]]
                 ], TypeConstruction.argument_typing_pairs(params: params, arguments: arguments)
  end

  def test_parameter_types
    type = parse_method_type("(Integer, ?String, *Object, d: String, ?e: Symbol, **Float) -> any")
    args = parameters("def f(a, b=1, *c, d:, e: 2, **f); end")

    env = TypeConstruction.parameter_types(args, type)

    assert_any env do |key, value|
      key.name == :a && value == Types::Name.instance(name: :Integer)
    end
    assert_any env do |key, value|
      key.name == :b && value == Types::Name.instance(name: :String)
    end
    assert_any env do |key, value|
      key.name == :c && value == Types::Name.instance(name: :Array, params: [Types::Name.instance(name: :Object)])
    end
    assert_any env do |key, value|
      key.name == :d && value == Types::Name.instance(name: :String)
    end
    assert_any env do |key, value|
      key.name == :e && value == Types::Name.instance(name: :Symbol)
    end
    assert_any env do |key, value|
      key.name == :f && value == Types::Name.instance(name: :Hash,
                                                      params: [Types::Name.instance(name: :Symbol),
                                                               Types::Name.instance(name: :Float)])
    end
  end

  def test_parameter_types_error
    type = parse_method_type("(Integer, ?String, *Object, d: String, ?e: Symbol, **Float) -> any")
    args = parameters("def f(a, *c, d:, **f); end")

    env = TypeConstruction.parameter_types(args, type)

    refute TypeConstruction.valid_parameter_env?(env, args, type.params)

    assert_any env do |key, value|
      key.name == :a && value == Types::Name.instance(name: :Integer)
    end
    refute_any env do |key, _|
      key.name == :b
    end
    assert_any env do |key, value|
      key.name == :c && value == Types::Name.instance(name: :Array, params: [Types::Name.instance(name: :Object)])
    end
    assert_any env do |key, value|
      key.name == :d && value == Types::Name.instance(name: :String)
    end
    refute_any env do |key, _|
      key.name == :e
    end
    assert_any env do |key, value|
      key.name == :f && value == Types::Name.instance(name: :Hash,
                                                      params: [Types::Name.instance(name: :Symbol),
                                                               Types::Name.instance(name: :Float)])
    end
  end

  def test_union_type
    source = ruby("1")

    typing = Typing.new
    annotations = source.annotations(block: source.node)

    construction = TypeConstruction.new(assignability: assignability,
                                        source: source,
                                        annotations: annotations,
                                        var_types: {},
                                        block_context: nil,
                                        self_type: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil)

    assert_equal Types::Union.new(types: [Types::Name.interface(name: :_A), Types::Name.interface(name: :_C)]),
                 construction.union_type(Types::Name.interface(name: :_A), Types::Name.interface(name: :_C))

    assert_equal Types::Name.interface(name: :_A),
                 construction.union_type(Types::Name.interface(name: :_A), Types::Name.interface(name: :_A))
  end

  def test_module_self
    source = ruby(<<-EOF)
module Foo
  # @implements Foo
  
  block_given?
end
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)

    construction = TypeConstruction.new(assignability: assignability,
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
