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
    TypeAssignability.new.tap do |assignability|
      interfaces = Parser.parse_interfaces(<<-EOS)
interface A
  def +: (A) -> A
end

interface B
end

interface C
  def f: () -> A
  def g: (A, ?B) -> B
  def h: (a: A, ?b: B) -> C
end

interface D
  def foo: () -> any
end

interface X
  def f: () { (A) -> D } -> C 
end

interface Kernel
  def foo: (A) -> B
         : (C) -> D
end
      EOS
      interfaces.each do |interface|
        assignability.add_interface interface
      end
    end
  end

  def test_lvar_with_annotation
    source = ruby(<<-EOF)
# @type var x: A
x = nil
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)

    construction = TypeConstruction.new(assignability: assignability, source: source, annotations: annotations, var_types: {}, return_type: nil, block_type: nil, typing: typing)
    construction.synthesize(source.node)

    assert_equal Types::Name.interface(name: :A), typing.type_of(node: source.node)
    assert_empty typing.errors
  end

  def test_lvar_with_annotation_type_check
    source = ruby(<<-EOF)
# @type var x: B
# @type var z: A
x = nil
z = x
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)

    construction = TypeConstruction.new(assignability: assignability, source: source, annotations: annotations, var_types: {}, return_type: nil, block_type: nil, typing: typing)
    construction.synthesize(source.node)

    assert_equal Types::Name.interface(name: :A), typing.type_of(node: source.node)

    assert_equal 1, typing.errors.size
    assert_incompatible_assignment typing.errors[0],
                                   lhs_type: Types::Name.interface(name: :A),
                                   rhs_type: Types::Name.interface(name: :B) do |error|
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

    construction = TypeConstruction.new(assignability: assignability, source: source, annotations: annotations, var_types: {}, return_type: nil, block_type: nil, typing: typing)
    construction.synthesize(source.node)

    assert_equal Types::Any.new, typing.type_of(node: source.node)
    assert_empty typing.errors
  end

  def test_lvar_without_annotation_inference
    source = ruby(<<-EOF)
# @type var x: A
x = nil
z = x
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)

    construction = TypeConstruction.new(assignability: assignability, source: source, annotations: annotations, var_types: {}, return_type: nil, block_type: nil, typing: typing)
    construction.synthesize(source.node)

    assert_equal Types::Name.interface(name: :A), typing.type_of(node: source.node)
    assert_empty typing.errors
  end

  def test_method_call
    source = ruby(<<-EOF)
# @type var x: C
x = nil
x.f
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)

    construction = TypeConstruction.new(assignability: assignability, source: source, annotations: annotations, var_types: {}, return_type: nil, block_type: nil, typing: typing)
    construction.synthesize(source.node)

    assert_equal Types::Name.interface(name: :A), typing.type_of(node: source.node)
    assert_empty typing.errors
  end

  def test_method_call_with_argument
    source = ruby(<<-EOF)
# @type var x: C
# @type var y: A
x = nil
y = nil
x.g(y)
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)

    construction = TypeConstruction.new(assignability: assignability, source: source, annotations: annotations, var_types: {}, return_type: nil, block_type: nil, typing: typing)
    construction.synthesize(source.node)

    assert_equal Types::Name.interface(name: :B), typing.type_of(node: source.node)
    assert_empty typing.errors
  end

  def test_method_call_incompatible_argument_type
    source = ruby(<<-EOF)
# @type var x: C
# @type var y: B
x = nil
y = nil
x.g(y)
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)

    construction = TypeConstruction.new(assignability: assignability, source: source, annotations: annotations, var_types: {}, return_type: nil, block_type: nil, typing: typing)
    construction.synthesize(source.node)

    assert_equal Types::Any.new, typing.type_of(node: source.node)

    assert_equal 1, typing.errors.size
    assert_argument_type_mismatch typing.errors[0], type: Types::Name.interface(name: :C), method: :g
  end

  def test_method_call_no_error_if_any
    source = ruby(<<-EOF)
x = nil
x.no_such_method
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)

    construction = TypeConstruction.new(assignability: assignability, source: source, annotations: annotations, var_types: {}, return_type: nil, block_type: nil, typing: typing)
    construction.synthesize(source.node)

    assert_equal Types::Any.new, typing.type_of(node: source.node)
    assert_empty typing.errors
  end

  def test_method_call_no_method_error
    source = ruby(<<-EOF)
# @type var x: C
x = nil
x.no_such_method
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)

    construction = TypeConstruction.new(assignability: assignability, source: source, annotations: annotations, var_types: {}, return_type: nil, block_type: nil, typing: typing)
    construction.synthesize(source.node)

    assert_equal Types::Any.new, typing.type_of(node: source.node)

    assert_equal 1, typing.errors.size
    assert_no_method_error typing.errors.first, method: :no_such_method, type: Types::Name.interface(name: :C)
  end

  def test_method_call_missing_argument
    source = ruby(<<-EOF)
# @type var x: A
# @type var a: C
a = nil
x = nil
a.g()
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)

    construction = TypeConstruction.new(assignability: assignability, source: source, annotations: annotations, var_types: {}, return_type: nil, block_type: nil, typing: typing)
    construction.synthesize(source.node)

    assert_equal Types::Any.new, typing.type_of(node: source.node)

    assert_equal 1, typing.errors.size
    assert_argument_type_mismatch typing.errors[0], type: Types::Name.interface(name: :C), method: :g
  end

  def test_method_call_extra_args
    source = ruby(<<-EOF)
# @type var x: A
# @type var a: C
a = nil
x = nil
a.g(nil, nil, nil)
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)

    construction = TypeConstruction.new(assignability: assignability, source: source, annotations: annotations, var_types: {}, return_type: nil, block_type: nil, typing: typing)
    construction.synthesize(source.node)

    assert_equal Types::Any.new, typing.type_of(node: source.node)

    assert_equal 1, typing.errors.size
    assert_argument_type_mismatch typing.errors.first, type: Types::Name.interface(name: :C), method: :g
  end

  def test_keyword_call
    source = ruby(<<-EOF)
# @type var x: C
# @type var a: A
# @type var b: B
x = nil
a = nil
b = nil
x.h(a: a, b: b)
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)

    construction = TypeConstruction.new(assignability: assignability, source: source, annotations: annotations, var_types: {}, return_type: nil, block_type: nil, typing: typing)
    construction.synthesize(source.node)

    assert_equal Types::Name.interface(name: :C), typing.type_of(node: source.node)
    assert_empty typing.errors
  end

  def test_keyword_missing
    source = ruby(<<-EOF)
# @type var x: C
x = nil
x.h()
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)

    construction = TypeConstruction.new(assignability: assignability, source: source, annotations: annotations, var_types: {}, return_type: nil, block_type: nil, typing: typing)
    construction.synthesize(source.node)

    assert_equal Types::Any.new, typing.type_of(node: source.node)

    assert_equal 1, typing.errors.size
    assert_argument_type_mismatch typing.errors[0], type: Types::Name.interface(name: :C), method: :h
  end

  def test_extra_keyword_given
    source = ruby(<<-EOF)
# @type var x: C
x = nil
x.h(a: nil, b: nil, c: nil)
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)

    construction = TypeConstruction.new(assignability: assignability, source: source, annotations: annotations, var_types: {}, return_type: nil, block_type: nil, typing: typing)
    construction.synthesize(source.node)

    assert_equal Types::Any.new, typing.type_of(node: source.node)

    assert_equal 1, typing.errors.size
    assert_argument_type_mismatch typing.errors[0], type: Types::Name.interface(name: :C), method: :h
  end

  def test_keyword_typecheck
    source = ruby(<<-EOF)
# @type var x: C
# @type var y: B
x = nil
y = nil
x.h(a: y)
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)

    construction = TypeConstruction.new(assignability: assignability, source: source, annotations: annotations, var_types: {}, return_type: nil, block_type: nil, typing: typing)
    construction.synthesize(source.node)

    assert_equal Types::Any.new, typing.type_of(node: source.node)

    assert_equal 1, typing.errors.size
    assert_argument_type_mismatch typing.errors[0], type: Types::Name.interface(name: :C), method: :h
  end

  def test_def_no_params
    source = ruby(<<-EOF)
def foo
  # @type var x: A
  x = nil
end
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)

    construction = TypeConstruction.new(assignability: assignability, source: source, annotations: annotations, var_types: {}, return_type: nil, block_type: nil, typing: typing)
    construction.synthesize(source.node)

    def_body = source.node.children[2]
    assert_equal Types::Name.interface(name: :A), typing.type_of(node: def_body)
  end

  def test_def_param
    source = ruby(<<-EOF)
def foo(x)
  # @type var x: A
  y = x
end
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)

    construction = TypeConstruction.new(assignability: assignability, source: source, annotations: annotations, var_types: {}, return_type: nil, block_type: nil, typing: typing)
    construction.synthesize(source.node)

    def_body = source.node.children[2]
    assert_equal Types::Name.interface(name: :A), typing.type_of(node: def_body)
    assert_equal Types::Name.interface(name: :A), typing.type_of_variable(name: :x)
    assert_equal Types::Name.interface(name: :A), typing.type_of_variable(name: :y)
  end

  def test_def_param_error
    source = ruby(<<-EOF)
def foo(x, y = x)
  # @type var x: A
  # @type var y: C
end
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)

    construction = TypeConstruction.new(assignability: assignability, source: source, annotations: annotations, var_types: {}, return_type: nil, block_type: nil, typing: typing)
    construction.synthesize(source.node)

    refute_empty typing.errors
    assert_incompatible_assignment typing.errors[0],
                                   lhs_type: Types::Name.interface(name: :C),
                                   rhs_type: Types::Name.interface(name: :A) do |error|
      assert_equal :optarg, error.node.type
      assert_equal :y, error.node.children[0].name
    end

    assert_equal Types::Name.interface(name: :A), typing.type_of_variable(name: :x)
    assert_equal Types::Name.interface(name: :C), typing.type_of_variable(name: :y)
  end

  def test_def_kw_param_error
    source = ruby(<<-EOF)
def foo(x:, y: x)
  # @type var x: A
  # @type var y: C
end
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)

    construction = TypeConstruction.new(assignability: assignability, source: source, annotations: annotations, var_types: {}, return_type: nil, block_type: nil, typing: typing)
    construction.synthesize(source.node)

    refute_empty typing.errors
    assert_incompatible_assignment typing.errors[0],
                                   lhs_type: Types::Name.interface(name: :C),
                                   rhs_type: Types::Name.interface(name: :A) do |error|
      assert_equal :kwoptarg, error.node.type
      assert_equal :y, error.node.children[0].name
    end

    assert_equal Types::Name.interface(name: :A), typing.type_of_variable(name: :x)
    assert_equal Types::Name.interface(name: :C), typing.type_of_variable(name: :y)
  end

  def test_block
    source = ruby(<<-EOF)
# @type var a: X
a = nil

b = a.f do |x|
  # @type var x: A
  # @type var y: B
  y = nil
end
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)

    construction = TypeConstruction.new(assignability: assignability, source: source, annotations: annotations, var_types: {}, return_type: nil, block_type: nil, typing: typing)
    construction.synthesize(source.node)

    assert_equal Types::Name.interface(name: :X), typing.type_of_variable(name: :a)
    assert_equal Types::Name.interface(name: :C), typing.type_of_variable(name: :b)
    assert_equal Types::Name.interface(name: :A), typing.type_of_variable(name: :x)
    assert_equal Types::Name.interface(name: :B), typing.type_of_variable(name: :y)
  end

  def test_block_shadow
    source = ruby(<<-EOF)
# @type var a: X
a = nil

a.f do |a|
  # @type var a: A
  b = a
end
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)

    construction = TypeConstruction.new(assignability: assignability, source: source, annotations: annotations, var_types: {}, return_type: nil, block_type: nil, typing: typing)
    construction.synthesize(source.node)

    assert_any typing.var_typing do |var, type| var.name == :a && type.is_a?(Types::Name) && type.name == TypeName::Interface.new(name: :A) end
    assert_any typing.var_typing do |var, type| var.name == :a && type.is_a?(Types::Name) && type.name == TypeName::Interface.new(name: :X) end
    assert_equal Types::Name.interface(name: :A), typing.type_of_variable(name: :b)
  end

  def test_block_param_type
    source = ruby(<<-EOF)
# @type var x: X
x = nil

x.f do |a|
  # @type var d: D
  d = nil
end
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)

    construction = TypeConstruction.new(assignability: assignability, source: source, annotations: annotations, var_types: {}, return_type: nil, block_type: nil, typing: typing)
    construction.synthesize(source.node)

    assert_equal Types::Name.interface(name: :X), typing.type_of_variable(name: :x)
    assert_equal Types::Name.interface(name: :A), typing.type_of_variable(name: :a)
    assert_equal Types::Name.interface(name: :D), typing.type_of_variable(name: :d)
    assert_empty typing.errors
  end

  def test_block_value_type
    source = ruby(<<-EOF)
# @type var x: X
x = nil

x.f do |a|
  a
end
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)

    construction = TypeConstruction.new(assignability: assignability, source: source, annotations: annotations, var_types: {}, return_type: nil, block_type: nil, typing: typing)
    construction.synthesize(source.node)

    assert_equal Types::Name.interface(name: :X), typing.type_of_variable(name: :x)
    assert_equal Types::Name.interface(name: :A), typing.type_of_variable(name: :a)

    assert_equal 1, typing.errors.size
    assert_block_type_mismatch typing.errors[0], expected: Types::Name.interface(name: :D), actual: Types::Name.interface(name: :A)
  end

  def test_block_break_type
    source = ruby(<<-EOF)
# @type var x: X
x = nil

x.f do |a|
  break a
  # @type var d: D
  d = nil
end
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)

    construction = TypeConstruction.new(assignability: assignability, source: source, annotations: annotations, var_types: {}, return_type: nil, block_type: nil, typing: typing)
    construction.synthesize(source.node)

    assert_equal Types::Name.interface(name: :X), typing.type_of_variable(name: :x)
    assert_equal Types::Name.interface(name: :A), typing.type_of_variable(name: :a)

    assert_equal 1, typing.errors.size
    assert_break_type_mismatch typing.errors[0], expected: Types::Name.interface(name: :C), actual: Types::Name.interface(name: :A)
  end

  def test_return_type
    source = ruby(<<-EOF)
def foo()
  # @type return: A
  # @type var a: A
  a = nil
  return a
end
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)

    construction = TypeConstruction.new(assignability: assignability, source: source, annotations: annotations, var_types: {}, return_type: nil, block_type: nil, typing: typing)
    construction.synthesize(source.node)

    assert_empty typing.errors
  end

  def test_return_error
    source = ruby(<<-EOF)
def foo()
  # @type return: X
  # @type var a: A
  a = nil
  return a
end
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)

    construction = TypeConstruction.new(assignability: assignability, source: source, annotations: annotations, var_types: {}, return_type: nil, block_type: nil, typing: typing)
    construction.synthesize(source.node)

    assert_any typing.errors do |error|
      error.is_a?(Steep::Errors::ReturnTypeMismatch) && error.expected == Types::Name.interface(name: :X) && error.actual == Types::Name.interface(name: :A)
    end
  end

  def test_union_method
    source = ruby(<<-EOF)
# @type var k: Kernel
# @type var a: A
# @type var c: C
k = nil
a = nil
c = nil

# @type var b: B
# b = k.foo(a)

# @type var d: D
d = k.foo(c)
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)

    construction = TypeConstruction.new(assignability: assignability, source: source, annotations: annotations, var_types: {}, return_type: nil, block_type: nil, typing: typing)
    construction.synthesize(source.node)

    assert_empty typing.errors
  end

  def arguments(ruby)
    ::Parser::CurrentRuby.parse(ruby).children.drop(2)
  end

  def test_argument_pairs
    params = Interface::Params.empty.with(required: [Types::Name.interface(name: :A)],
                                          optional: [Types::Name.interface(name: :B)],
                                          rest: Types::Name.interface(name: :C),
                                          required_keywords: { d: Types::Name.interface(name: :D) },
                                          optional_keywords: { e: Types::Name.interface(name: :E) },
                                          rest_keywords: Types::Name.interface(name: :F))
    arguments = arguments("f(a, b, c, d: d, e: e, f: f)")

    assert_equal [
                   [Types::Name.interface(name: :A), arguments[0]],
                   [Types::Name.interface(name: :B), arguments[1]],
                   [Types::Name.interface(name: :C), arguments[2]],
                   [Types::Name.interface(name: :D), arguments[3].children[0].children[1]],
                   [Types::Name.interface(name: :E), arguments[3].children[1].children[1]],
                   [Types::Name.interface(name: :F), arguments[3].children[2].children[1]]
                 ], TypeConstruction.argument_typing_pairs(params: params, arguments: arguments)
  end

  def test_argument_pairs_rest_keywords
    params = Interface::Params.empty.with(required: [Types::Name.interface(name: :A)],
                                          optional: [Types::Name.interface(name: :B)],
                                          rest: Types::Name.interface(name: :C),
                                          required_keywords: { d: Types::Name.interface(name: :D) },
                                          optional_keywords: { e: Types::Name.interface(name: :E) },
                                          rest_keywords: Types::Name.interface(name: :F))
    arguments = arguments("f(a, b, c, d: d, e: e, f: f)")

    assert_equal [
                   [Types::Name.interface(name: :A), arguments[0]],
                   [Types::Name.interface(name: :B), arguments[1]],
                   [Types::Name.interface(name: :C), arguments[2]],
                   [Types::Name.interface(name: :D), arguments[3].children[0].children[1]],
                   [Types::Name.interface(name: :E), arguments[3].children[1].children[1]],
                   [Types::Name.interface(name: :F), arguments[3].children[2].children[1]]
                 ], TypeConstruction.argument_typing_pairs(params: params, arguments: arguments)
  end

  def test_argument_pairs_required
    params = Interface::Params.empty.with(required: [Types::Name.interface(name: :A)],
                                          optional: [Types::Name.interface(name: :B)],
                                          rest: Types::Name.interface(name: :C))
    arguments = arguments("f(a, b, c)")

    assert_equal [
                   [Types::Name.interface(name: :A), arguments[0]],
                   [Types::Name.interface(name: :B), arguments[1]],
                   [Types::Name.interface(name: :C), arguments[2]],
                 ], TypeConstruction.argument_typing_pairs(params: params, arguments: arguments)
  end

  def test_argument_pairs_hash
    params = Interface::Params.empty.with(required: [Types::Name.interface(name: :A)],
                                          optional: [Types::Name.interface(name: :B)],
                                          rest: Types::Name.interface(name: :C))
    arguments = arguments("f(a, b, c, d: d)")

    assert_equal [
                   [Types::Name.interface(name: :A), arguments[0]],
                   [Types::Name.interface(name: :B), arguments[1]],
                   [Types::Name.interface(name: :C), arguments[2]],
                   [Types::Name.interface(name: :C), arguments[3]]
                 ], TypeConstruction.argument_typing_pairs(params: params, arguments: arguments)
  end

  def test_argument_keywords
    params = Interface::Params.empty.with(required_keywords: { d: Types::Name.interface(name: :D) },
                                          optional_keywords: { e: Types::Name.interface(name: :E) },
                                          rest_keywords: Types::Name.interface(name: :F))

    arguments = arguments("f(d: d, e: e, f: f)")

    assert_equal [
                   [Types::Name.interface(name: :D), arguments[0].children[0].children[1]],
                   [Types::Name.interface(name: :E), arguments[0].children[1].children[1]],
                   [Types::Name.interface(name: :F), arguments[0].children[2].children[1]],
                 ], TypeConstruction.argument_typing_pairs(params: params, arguments: arguments)
  end

  def test_argument_hash_not_keywords
    params = Interface::Params.empty.with(required: [Types::Name.interface(name: :A)])

    arguments = arguments("f(d: d, e: e, f: f)")

    assert_equal [
                   [Types::Name.interface(name: :A), arguments[0]]
                 ], TypeConstruction.argument_typing_pairs(params: params, arguments: arguments)
  end
end
