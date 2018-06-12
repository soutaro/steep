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
  TypeEnv = Steep::TypeInference::TypeEnv

  include TestHelper
  include TypeErrorAssertions
  include SubtypingHelper

  def test_lvar_with_annotation
    source = parse_ruby(<<-EOF)
# @type var x: _A
x = (_ = nil)
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = new_subtyping_checker()
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
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
x = (_ = nil)
z = x
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = new_subtyping_checker()
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
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
    checker = new_subtyping_checker()
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
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
x = (_ = nil)
z = x
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = new_subtyping_checker()
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
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
x = (_ = nil)
x.f
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = new_subtyping_checker()
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
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
x = (_ = nil)
y = (_ = nil)
x.g(y)
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = new_subtyping_checker()
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
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
x = (_ = nil)
y = (_ = nil)
x.g(y)
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = new_subtyping_checker()
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
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
x = (_ = nil)
x.no_such_method
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = new_subtyping_checker
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
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
x = (_ = nil)
x.no_such_method
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = new_subtyping_checker()
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
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
a = (_ = nil)
x = (_ = nil)
a.g()
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = new_subtyping_checker()
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
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
a = (_ = nil)
x = (_ = nil)
a.g(_ = nil, _ = nil, _ = nil)
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = new_subtyping_checker()
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
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
x = (_ = nil)
a = (_ = nil)
b = (_ = nil)
x.h(a: a, b: b)
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = new_subtyping_checker()
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
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
x = (_ = nil)
x.h()
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = new_subtyping_checker()
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
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
x = (_ = nil)
x.h(a: (_ = nil), b: (_ = nil), c: (_ = nil))
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = new_subtyping_checker()
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
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
x = (_ = nil)
y = (_ = nil)
x.h(a: y)
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = new_subtyping_checker()
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
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
  x = (_ = nil)
end
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = new_subtyping_checker()
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
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
    checker = new_subtyping_checker()
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
                                        block_context: nil,
                                        self_type: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)
    construction.synthesize(source.node)

    def_body = source.node.children[2]
    assert_equal Types::Name.new_interface(name: :_A), typing.type_of(node: def_body)
    assert_equal Types::Name.new_interface(name: :_A), typing.type_of(node: def_body.children[1])
  end

  def test_def_param_error
    source = parse_ruby(<<-EOF)
def foo(x, y = x)
  # @type var x: _A
  # @type var y: _C
  x
  y
end
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = new_subtyping_checker()
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
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

    x = dig(source.node, 2, 0)
    y = dig(source.node, 2, 1)

    assert_equal Types::Name.new_interface(name: :_A), typing.type_of(node: x)
    assert_equal Types::Name.new_interface(name: :_C), typing.type_of(node: y)
  end

  def test_def_kw_param_error
    source = parse_ruby(<<-EOF)
def foo(x:, y: x)
  # @type var x: _A
  # @type var y: _C
  x
  y
end
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = new_subtyping_checker()
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
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

    x = dig(source.node, 2, 0)
    y = dig(source.node, 2, 1)

    assert_equal Types::Name.new_interface(name: :_A), typing.type_of(node: x)
    assert_equal Types::Name.new_interface(name: :_C), typing.type_of(node: y)
  end

  def test_block
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

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = new_subtyping_checker()
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
                                        block_context: nil,
                                        self_type: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)
    construction.synthesize(source.node)

    a = dig(source.node, 2)
    b = dig(source.node, 3)
    x = dig(source.node, 1, 1, 2, 1)
    y = dig(source.node, 1, 1, 2, 2)

    assert_equal Types::Name.new_interface(name: :_X), typing.type_of(node: a)
    assert_equal Types::Name.new_interface(name: :_C), typing.type_of(node: b)
    assert_equal Types::Name.new_interface(name: :_A), typing.type_of(node: x)
    assert_equal Types::Name.new_interface(name: :_B), typing.type_of(node: y)
  end

  def test_block_shadow
    source = parse_ruby(<<-EOF)
# @type var a: _X
a = (_ = nil)

a.f do |a|
  # @type var a: _A
  b = a
end
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = new_subtyping_checker()
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
                                        block_context: nil,
                                        self_type: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)
    construction.synthesize(source.node)

    block_body = dig(source.node, 1, 2)

    assert_equal Types::Name.new_interface(name: :_X), typing.type_of(node: lvar_in(source.node, :a))
    assert_equal Types::Name.new_interface(name: :_A), typing.type_of(node: lvar_in(block_body, :a))
    assert_equal Types::Name.new_interface(name: :_A), typing.type_of(node: lvar_in(block_body, :b))
  end

  def test_block_param_type
    source = parse_ruby(<<-EOF)
# @type var x: _X
x = (_ = nil)

x.f do |a|
  # @type var d: _D
  a
  d = (_ = nil)
end
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = new_subtyping_checker()
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
                                        block_context: nil,
                                        self_type: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)
    construction.synthesize(source.node)

    assert_equal Types::Name.new_interface(name: :_X), typing.type_of(node: lvar_in(source.node, :x))
    assert_equal Types::Name.new_interface(name: :_A), typing.type_of(node: lvar_in(source.node, :a))
    assert_equal Types::Name.new_interface(name: :_D), typing.type_of(node: lvar_in(source.node, :d))
    assert_empty typing.errors
  end

  def test_block_value_type
    source = parse_ruby(<<-EOF)
# @type var x: _X
x = (_ = nil)

x.f do |a|
  a
end
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = new_subtyping_checker()
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
                                        block_context: nil,
                                        self_type: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)
    construction.synthesize(source.node)

    assert_equal 1, typing.errors.size
    assert_block_type_mismatch typing.errors[0], expected: Types::Name.new_interface(name: :_D), actual: Types::Name.new_interface(name: :_A)

    assert_equal Types::Name.new_interface(name: :_X), typing.type_of(node: lvar_in(source.node, :x))
    assert_equal Types::Any.new, typing.type_of(node: lvar_in(source.node, :a))
  end

  def test_block_break_type
    source = parse_ruby(<<-EOF)
# @type var x: _X
x = (_ = nil)

x.f do |a|
  break a
  # @type var d: _D
  d = (_ = nil)
end
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = new_subtyping_checker()
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
                                        block_context: nil,
                                        self_type: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)
    construction.synthesize(source.node)

    assert_equal Types::Name.new_interface(name: :_X), typing.type_of(node: lvar_in(source.node, :x))
    assert_equal Types::Name.new_interface(name: :_A), typing.type_of(node: lvar_in(source.node, :a))

    assert_equal 1, typing.errors.size
    assert_break_type_mismatch typing.errors[0], expected: Types::Name.new_interface(name: :_C), actual: Types::Name.new_interface(name: :_A)
  end

  def test_return_type
    source = parse_ruby(<<-EOF)
def foo()
  # @type return: _A
  # @type var a: _A
  a = (_ = nil)
  return a
end
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = new_subtyping_checker()
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
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
  a = (_ = nil)
  return a
end
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = new_subtyping_checker()
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
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
    checker = new_subtyping_checker()
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    module_context = TypeConstruction::ModuleContext.new(
      instance_type: nil,
      module_type: nil,
      implement_name: nil,
      current_namespace: nil,
      const_env: const_env
    )

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
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
    checker = new_subtyping_checker()
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)

    module_context = TypeConstruction::ModuleContext.new(
      instance_type: nil,
      module_type: nil,
      implement_name: nil,
      current_namespace: nil,
      const_env: env
    )

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
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

    assert_equal Types::Name.new_instance(name: "::Integer"), typing.type_of(node: source.node)
  end

  def test_constant_signature
    source = parse_ruby(<<-EOF)
# @type var x: String
x = String
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = new_subtyping_checker()
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)

    module_context = TypeConstruction::ModuleContext.new(
      instance_type: nil,
      module_type: nil,
      implement_name: nil,
      current_namespace: nil,
      const_env: env
    )

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
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
    checker = new_subtyping_checker(<<-EOF)
X: Module
    EOF
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    module_context = TypeConstruction::ModuleContext.new(
      instance_type: nil,
      module_type: nil,
      implement_name: nil,
      current_namespace: nil,
      const_env: const_env
    )

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
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
k = (_ = nil)
a = (_ = nil)
c = (_ = nil)

# @type var b: _B
# b = k.foo(a)

# @type var d: _D
d = k.foo(c)
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = new_subtyping_checker()
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
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
  
  y = (_ = nil)
  
  @x = y
  y = @x
end
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = new_subtyping_checker()
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
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
poly = (_ = nil)

# @type var string: String
string = poly.snd(1, "a")
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = new_subtyping_checker()
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
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
poly = (_ = nil)

# @type var string: String
string = poly.try { "string" }
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = new_subtyping_checker()
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
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
    checker = new_subtyping_checker()
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
                                        block_context: nil,
                                        self_type: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)

    assert_equal Types::Union.build(types: [Types::Name.new_interface(name: :_A), Types::Name.new_interface(name: :_C)]),
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
    checker = new_subtyping_checker()
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
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
    checker = new_subtyping_checker(<<EOF)
class Person
end
EOF
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
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
    checker = new_subtyping_checker(<<EOF)
class Address
end
EOF
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
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
    checker = new_subtyping_checker(<<EOF)
class Steep::ModuleName
end
EOF
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    module_context = TypeConstruction::ModuleContext.new(
      instance_type: Types::Name.new_instance(name: "::Steep"),
      module_type: Types::Name.new_module(name: "::Steep"),
      implement_name: nil,
      current_namespace: Steep::ModuleName.parse("::Steep"),
      const_env: const_env
    )

    module_name_class_node = source.node.children[1]

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
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
    checker = new_subtyping_checker(<<EOF)
module Steep
end
EOF
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
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
      Types::Intersection.build(
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
    checker = new_subtyping_checker(<<EOF)
module Rails
end
EOF
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
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
    checker = new_subtyping_checker(<<EOF)
module Steep::Printable
end
EOF
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    module_context = TypeConstruction::ModuleContext.new(
      instance_type: Types::Name.new_instance(name: "::Steep"),
      module_type: Types::Name.new_class(name: "::Steep", constructor: false),
      implement_name: nil,
      current_namespace: Steep::ModuleName.parse("::Steep"),
      const_env: const_env
    )

    module_node = source.node.children.last

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
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
    checker = new_subtyping_checker(<<-EOF)
class A
  def foo: (String) -> Integer
end
    EOF
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
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
    assert_equal [:x], for_method.type_env.lvar_types.keys
    assert_equal Types::Name.new_instance(name: "::String"),
                 for_method.type_env.lvar_types[:x]
  end

  def test_new_method_constructor_union
    source = parse_ruby("class A; def foo(x, **y); end; end")
    def_node = source.node.children[2]

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = new_subtyping_checker(<<-EOF)
class A
  def foo: (String) -> Integer
         | (Object) -> Integer
end
    EOF
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
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
    assert_empty for_method.type_env.lvar_types

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
    checker = new_subtyping_checker(<<-EOF)
class A
  def foo: (String) -> Integer
end
    EOF
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
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
    assert_equal [:x], for_method.type_env.lvar_types.keys
    assert_equal Types::Name.new_instance(name: "::String"), for_method.type_env.lvar_types[:x]

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
    checker = new_subtyping_checker(<<-EOF)
class A
  def foo: (String) -> Integer
end
    EOF
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
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
    checker = new_subtyping_checker(<<-EOF)
class A::String
  def aaaaa: -> any
end
    EOF
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
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
    checker = new_subtyping_checker(<<-EOF)
class A
  def foobar: -> any
end

class A::String
  def aaaaa: -> any
end
    EOF
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
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
    checker = new_subtyping_checker(<<-EOF)
class A
end

class A::String
  def foo: -> any
end
    EOF
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
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
    checker = new_subtyping_checker(<<-EOF)
class A
end

class A::String
  def foo: -> any
end
    EOF
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
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
    checker = new_subtyping_checker()
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
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
    checker = new_subtyping_checker()
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
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

  def test_masgn_union
    source = parse_ruby(<<-EOF)
# @type var x: Array<Integer> | Array<String>
x = (_ = nil)
a, b = x
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = new_subtyping_checker()
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
                                        self_type: nil,
                                        block_context: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)

    construction.synthesize(source.node)

    assert_empty typing.errors
    union = Types::Union.build(types: [
      Types::Name.new_instance(name: "::Integer"),
      Types::Name.new_instance(name: "::String")
    ])
    assert_equal union, type_env.lvar_types[:a]
    assert_equal union, type_env.lvar_types[:b]
  end

  def test_masgn_array_error
    source = parse_ruby(<<-EOF)
a, @b = 3
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = new_subtyping_checker()
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
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
    checker = new_subtyping_checker()
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
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
    checker = new_subtyping_checker()
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
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
    checker = new_subtyping_checker()
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
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
    checker = new_subtyping_checker()
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
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
    checker = new_subtyping_checker()
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
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
    checker = new_subtyping_checker()
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
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
    checker = new_subtyping_checker()
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
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
    checker = new_subtyping_checker()
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
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
    checker = new_subtyping_checker()
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
                                        self_type: Types::Name.new_instance(name: "::Object"),
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

  def test_next
    source = parse_ruby(<<-'EOF')
while true
  next
end
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = new_subtyping_checker()
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
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
    checker = new_subtyping_checker()
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
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
    checker = new_subtyping_checker()
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
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
    checker = new_subtyping_checker()
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
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
    checker = new_subtyping_checker()
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
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
    checker = new_subtyping_checker()
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
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
    checker = new_subtyping_checker(<<-EOF)
$HOGE: Integer
    EOF
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
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
    checker = new_subtyping_checker(<<-EOF)
$HOGE: Integer
    EOF
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
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
    checker = new_subtyping_checker()
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
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
    checker = new_subtyping_checker(<<-EOF)
class A
  def foo: -> String
  @foo: String
end
    EOF
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
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
    checker = new_subtyping_checker(<<-EOF)
class A
  @foo: String
end
    EOF
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
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
    checker = new_subtyping_checker()
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
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
    checker = new_subtyping_checker()
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
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

  def test_splat_object
    source = parse_ruby(<<-'EOF')
# @type var a: Array<Symbol> | Integer
a = (_ = nil)
b = [*a, *["foo"]]
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = new_subtyping_checker()
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
                                        self_type: Types::Name.new_instance(name: "::Object"),
                                        block_context: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)

    construction.synthesize(source.node)

    assert_empty typing.errors
    assert_equal Types::Name.new_instance(name: "::Array",
                                          args: [Types::Union.build(types: [
                                            Types::Name.new_instance(name: "::Integer"),
                                            Types::Name.new_instance(name: "::Symbol"),
                                            Types::Name.new_instance(name: "::String")
                                          ])]),
                 type_env.lvar_types[:b]
  end

  def test_splat_arg
    source = parse_ruby(<<-'EOF')
a = A.new
a.gen(*["1"])
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = new_subtyping_checker(<<-EOF)
class A
  def initialize: () -> any
  def gen: (*Integer) -> String
end
    EOF
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    module_context = TypeConstruction::ModuleContext.new(
      instance_type: nil,
      module_type: nil,
      implement_name: nil,
      current_namespace: nil,
      const_env: const_env
    )

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
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
    checker = new_subtyping_checker(<<-EOF)
class Hoge
  def foo: (self) -> void
end
    EOF
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    module_context = TypeConstruction::ModuleContext.new(
      instance_type: nil,
      module_type: nil,
      implement_name: nil,
      current_namespace: nil,
      const_env: const_env
    )

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
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
    checker = new_subtyping_checker(<<-EOF)
class Hoge
  def foo: () { () -> void } -> any
end
    EOF
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    module_context = TypeConstruction::ModuleContext.new(
      instance_type: nil,
      module_type: nil,
      implement_name: nil,
      current_namespace: nil,
      const_env: const_env
    )

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
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

  def test_zip
    source = parse_ruby(<<EOF)
a = [1]

# @type var b: ::Array<Integer|String>
b = a.zip(["foo"])
EOF
    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = new_subtyping_checker("")
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
                                        block_context: nil,
                                        self_type: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)
    construction.synthesize(source.node)

    assert_empty typing.errors
  end

  def test_each_with_object
    source = parse_ruby(<<EOF)
a = [1]

# @type var b: ::Array<Integer>
b = a.each_with_object([]) do |x, y|
  # @type var y: ::Array<String>
  y << ""
end
EOF
    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = new_subtyping_checker("")
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
                                        block_context: nil,
                                        self_type: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)
    construction.synthesize(source.node)

    refute_empty typing.errors
    assert_instance_of Steep::Errors::IncompatibleAssignment, typing.errors[0]
  end

  def test_if_typing
    source = parse_ruby(<<EOF)
if 3
  x = 1
  y = (x + 1).to_int
else
  x = "foo"
  y = (x.to_str).size
end
EOF
    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = new_subtyping_checker("")
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
                                        block_context: nil,
                                        self_type: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)
    construction.synthesize(source.node)

    assert_empty typing.errors
    assert_equal Types::Union.build(types: [Types::Name.new_instance(name: "::String"),
                                            Types::Name.new_instance(name: "::Integer")]),
                 type_env.lvar_types[:x]
    assert_equal Types::Name.new_instance(name: "::Integer"),
                 type_env.lvar_types[:y]
  end

  def test_if_annotation
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
    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = new_subtyping_checker("")
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
                                        block_context: nil,
                                        self_type: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)

    if_node = dig(source.node, 1)

    true_construction = construction.for_branch(if_node.children[1])
    assert_equal Types::Name.new_instance(name: "::String"), true_construction.type_env.lvar_types[:x]

    false_construction = construction.for_branch(if_node.children[2])
    assert_equal Types::Name.new_instance(name: "::Integer"), false_construction.type_env.lvar_types[:x]

    construction.synthesize(source.node)
    assert_empty typing.errors
  end

  def test_if_annotation_error
    source = parse_ruby(<<EOF)
# @type var x: Array<String>
x = (_ = nil)

if 3
  # @type var x: String
  x + ""
else
  # @type var x: Integer
  x + 1
end
EOF
    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = new_subtyping_checker("")
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
                                        block_context: nil,
                                        self_type: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)

    construction.synthesize(source.node)

    if_node = dig(source.node, 1)

    true_construction = construction.for_branch(if_node.children[1])
    assert_equal Types::Name.new_instance(name: "::String"), true_construction.type_env.lvar_types[:x]

    false_construction = construction.for_branch(if_node.children[2])
    assert_equal Types::Name.new_instance(name: "::Integer"), false_construction.type_env.lvar_types[:x]

    typing.errors.find {|error| error.node == if_node.children[1] }.yield_self do |error|
      assert_instance_of Steep::Errors::IncompatibleAnnotation, error
      assert_equal :x, error.var_name
    end

    typing.errors.find {|error| error.node == if_node.children[2] }.yield_self do |error|
      assert_instance_of Steep::Errors::IncompatibleAnnotation, error
      assert_equal :x, error.var_name
    end
  end

  def test_when_typing
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
    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = new_subtyping_checker("")
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
                                        block_context: nil,
                                        self_type: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)
    construction.synthesize(source.node)

    assert_empty typing.errors
    assert_equal Types::Union.build(types: [Types::Name.new_instance(name: "::String"),
                                            Types::Name.new_instance(name: "::Integer")]),
                 type_env.lvar_types[:x]
    assert_equal Types::Name.new_instance(name: "::Integer"),
                 type_env.lvar_types[:y]
  end

  def test_where_typing
    source = parse_ruby(<<EOF)
# @type var x: Integer | String
x = (_ = nil)

while 3
  # @type var x: Integer
  x + 3 
end
EOF
    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = new_subtyping_checker("")
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
                                        block_context: nil,
                                        self_type: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)
    construction.synthesize(source.node)

    assert_empty typing.errors
  end

  def test_rescue_typing
    source = parse_ruby(<<EOF)
# @type const E: any
# @type const F: any

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
    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = new_subtyping_checker("")
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
                                        block_context: nil,
                                        self_type: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)
    construction.synthesize(source.node)

    assert_empty typing.errors
    assert_equal Types::Union.build(types: [Types::Name.new_instance(name: "::String"),
                                            Types::Name.new_instance(name: "::Integer"),
                                            Types::Name.new_instance(name: "::Symbol")]),
                 type_env.lvar_types[:x]
  end

  def test_rescue_bidning_typing
    source = parse_ruby(<<EOF)
# @type const E: String.class
# @type const F: Integer.class

begin
  1 + 2
rescue E => exn
  exn + ""
rescue F => exn
  exn + 3
end
EOF
    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = new_subtyping_checker("")
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
                                        block_context: nil,
                                        self_type: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)
    construction.synthesize(source.node)

    assert_empty typing.errors
    assert_equal Types::Union.build(types: [Types::Name.new_instance(name: "::String"),
                                            Types::Name.new_instance(name: "::Integer")]),
                 type_env.lvar_types[:exn]
  end

  def test_type_case_case_when
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
    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = new_subtyping_checker("")
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
                                        block_context: nil,
                                        self_type: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)
    construction.synthesize(source.node)

    assert_empty typing.errors
  end

  def test_type_case_array
    source = parse_ruby(<<EOF)
# @type var x: Array<String> | Array<Integer> | Range<Symbol>
x = (_ = nil)

case x
when Array
  y = x[0]
  z = :foo
else
  z = x.begin
end
EOF
    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = new_subtyping_checker("")
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
                                        block_context: nil,
                                        self_type: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)
    construction.synthesize(source.node)

    assert_empty typing.errors
    assert_equal Types::Union.build(types:[Types::Name.new_instance(name: "::String"),
                                           Types::Name.new_instance(name: "::Integer"),
                                           Types::Nil.new]),
                 construction.type_env.lvar_types[:y]
    assert_equal Types::Name.new_instance(name: "::Symbol"),
                 construction.type_env.lvar_types[:z]
  end

  def test_type_case_array2
    source = parse_ruby(<<EOF)
# @type var x: Array<String> | Array<Integer>
x = (_ = nil)

case x
when Array
  y = x[0]
else
  z = x
end
EOF
    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = new_subtyping_checker("")
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
                                        block_context: nil,
                                        self_type: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)
    construction.synthesize(source.node)

    assert_equal 1, typing.errors.size
    typing.errors[0].yield_self do |error|
      assert_instance_of Steep::Errors::ElseOnExhaustiveCase, error
    end
  end

  def test_initialize_typing
    source = parse_ruby(<<EOF)
class Foo
  def initialize(foo)
  end
end
EOF
    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = new_subtyping_checker(<<EOS)
class Foo
  def initialize: (String) -> any
end
EOS
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
                                        block_context: nil,
                                        self_type: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)
    construction.synthesize(source.node)

    assert_empty typing.errors
  end

  def test_cast_via_underscore
    source = parse_ruby(<<EOF)
# @type var x: String
x = (_ = 3)
EOF
    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = new_subtyping_checker("")
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
                                        block_context: nil,
                                        self_type: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)
    construction.synthesize(source.node)

    assert_empty typing.errors
  end

  def test_parametrized_class_constant
    source = parse_ruby(<<EOF)
Array.new
EOF
    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = new_subtyping_checker("")
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
                                        block_context: nil,
                                        self_type: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)
    construction.synthesize(source.node)

    assert_empty typing.errors
  end

  def test_splat_from_any
    source = parse_ruby(<<EOF)
[].[]=(*(_ = nil))
EOF
    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = new_subtyping_checker("")
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
                                        block_context: nil,
                                        self_type: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)
    construction.synthesize(source.node)

    assert_empty typing.errors
  end

  def test_polymorphic
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

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = new_subtyping_checker(<<EOF)
class Optional
  def map: <'a, 'b> ('a) { ('a) -> 'b } -> 'b
  def map2: <'a, 'b> ('a) { ('a) -> 'b } -> 'b
end
EOF
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
                                        block_context: nil,
                                        self_type: nil,
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

  def test_parameterized_class
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

# @type var container: Container<Integer>
container = Container.new
container.value = 3
container.value + 4
EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = new_subtyping_checker(<<EOF)
class Container<'a>
  @value: 'a
  def initialize: () -> any
  def value: -> 'a
  def value=: ('a) -> 'a
end
EOF
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
                                        block_context: nil,
                                        self_type: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)
    construction.synthesize(source.node)

    assert_empty typing.errors
  end

  def test_parameterized_module
    source = parse_ruby(<<EOF)
module Value
  def value
    @value
  end
end
EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = new_subtyping_checker(<<EOF)
module Value<'a>
  @value: 'a
  def value: -> 'a
end
EOF
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
                                        block_context: nil,
                                        self_type: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)
    construction.synthesize(source.node)

    assert_empty typing.errors
  end

  def test_initialize
    source = parse_ruby(<<EOF)
hello = HelloWorld.new
EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = new_subtyping_checker(<<EOF)
class HelloWorld
end
EOF
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
                                        block_context: nil,
                                        self_type: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)
    construction.synthesize(source.node)

    assert_empty typing.errors
  end

  def test_initialize2
    source = parse_ruby(<<EOF)
# @type var hello: Integer
hello = Array.new(3, "")[0]
EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = new_subtyping_checker("")
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
                                        block_context: nil,
                                        self_type: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)
    construction.synthesize(source.node)

    assert_any typing.errors do |error|
      error.is_a?(Steep::Errors::IncompatibleAssignment) &&
        error.lhs_type == Types::Name.new_instance(name: "::Integer") &&
        error.rhs_type == Types::Name.new_instance(name: "::String")
    end
  end

  def test_initialize_unbound_type_var_fallback_to_any
    source = parse_ruby(<<EOF)
# @type var x: Integer    
x = Array.new(3)[0]
EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = new_subtyping_checker("")
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
                                        block_context: nil,
                                        self_type: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)
    construction.synthesize(source.node)

    assert_empty typing.errors
  end

  def test_truthy_variables
    assert_equal Set.new([:x]), TypeConstruction.truthy_variables(parse_ruby("x = 1").node)
    assert_equal Set.new([:x, :y]), TypeConstruction.truthy_variables(parse_ruby("x = y = 1").node)
    assert_equal Set.new([:x]), TypeConstruction.truthy_variables(parse_ruby("(x = 1) && f()").node)
  end

  def test_unwrap
    assert_equal Types::Name.new_instance(name: "::Integer"),
                 TypeConstruction.unwrap(
                   Types::Union.build(types: [
                     Types::Name.new_instance(name: "::Integer"),
                     Types::Nil.new
                   ])
                 )
  end

  def test_if_unwrap
    source = parse_ruby(<<EOF)
# @type var x: Integer?
x = nil

if x
  x + 1
end
EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = new_subtyping_checker("")
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
                                        block_context: nil,
                                        self_type: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)
    construction.synthesize(source.node)

    assert_empty typing.errors
  end

  def test_and_unwrap
    source = parse_ruby(<<EOF)
# @type var x: Integer?
x = nil
# @type var y1: Integer
y1 = 3

z = (x && y1 = y = x + 1)
EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = new_subtyping_checker("")
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
                                        block_context: nil,
                                        self_type: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)
    construction.synthesize(source.node)

    assert_empty typing.errors

    assert_equal Types::Union.build(types: [
      Types::Name.new_instance(name: "::Numeric"),
      Types::Nil.new
    ]), type_env.lvar_types[:y]

    assert_equal Types::Union.build(types: [
      Types::Name.new_instance(name: "::Integer"),
      Types::Nil.new
    ]), type_env.lvar_types[:z]
  end

  def test_csend_unwrap
    source = parse_ruby(<<EOF)
# @type var x: String?
x = nil

z = x&.size()
EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = new_subtyping_checker("")
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
                                        block_context: nil,
                                        self_type: nil,
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)
    construction.synthesize(source.node)

    assert_empty typing.errors

    assert_equal Types::Union.build(types: [
      Types::Name.new_instance(name: "::Integer"),
      Types::Nil.new
    ]), type_env.lvar_types[:z]
  end

  def test_while
    source = parse_ruby(<<EOF)
while line = gets
  # @type var x: String
  x = line
end
EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = new_subtyping_checker("")
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
                                        block_context: nil,
                                        self_type: Types::Name.new_instance(name: "::Object"),
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)
    construction.synthesize(source.node)

    assert_empty typing.errors

    assert_equal Types::Union.build(types: [
      Types::Name.new_instance(name: "::String"),
      Types::Nil.new
    ]), type_env.lvar_types[:line]
  end

  def test_case_non_exhaustive
    source = parse_ruby(<<EOF)
# @type var x: String | Integer
x = ""

y = case x
when String
  3
end
EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = new_subtyping_checker("")
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
                                        block_context: nil,
                                        self_type: Types::Name.new_instance(name: "::Object"),
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)
    construction.synthesize(source.node)

    assert_empty typing.errors

    assert_equal Types::Union.build(types: [
      Types::Name.new_instance(name: "::Integer"),
      Types::Nil.new
    ]), type_env.lvar_types[:y]
  end

  def test_case_exhaustive
    source = parse_ruby(<<EOF)
# @type var x: String | Integer
x = ""

y = case x
when String
  3
when Integer
  4
end
EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = new_subtyping_checker("")
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
                                        block_context: nil,
                                        self_type: Types::Name.new_instance(name: "::Object"),
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)
    construction.synthesize(source.node)

    assert_empty typing.errors

    assert_equal Types::Name.new_instance(name: "::Integer"), type_env.lvar_types[:y]
  end

  def test_case_exhaustive_else
    source = parse_ruby(<<EOF)
# @type var x: String | Integer

y = case (x = "")
when String
  3
else
  4
end
EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = new_subtyping_checker("")
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
                                        block_context: nil,
                                        self_type: Types::Name.new_instance(name: "::Object"),
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)
    construction.synthesize(source.node)

    assert_empty typing.errors

    assert_equal Types::Name.new_instance(name: "::Integer"), type_env.lvar_types[:y]
  end

  def test_def_with_splat_kwargs
    source = parse_ruby(<<EOF)
# @type method f: (**String) -> any
def f(**args)
  args[:foo] + "hoge"
end

def g(**xs)
end
EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = new_subtyping_checker("")
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
                                        block_context: nil,
                                        self_type: Types::Name.new_instance(name: "::Object"),
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)
    construction.synthesize(source.node)

    assert_equal 1, typing.errors.size
    typing.errors[0].yield_self do |error|
      assert_instance_of Steep::Errors::FallbackAny, error
    end
  end

  def test_splat_kw_args
    source = parse_ruby(<<EOF)
test = KWArgTest.new

params = { a: 123 }
test.foo(123, **params)
test.foo(123, **123)
EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = new_subtyping_checker(<<-EOF)
class KWArgTest
  def foo: (Integer, **String) -> void
end
    EOF
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
                                        block_context: nil,
                                        self_type: Types::Name.new_instance(name: "::Object"),
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)
    construction.synthesize(source.node)

    assert_equal 2, typing.errors.size
    assert_any typing.errors do |error|
      error.is_a?(Steep::Errors::ArgumentTypeMismatch)
    end
    assert_any typing.errors do |error|
      error.is_a?(Steep::Errors::UnexpectedSplat)
    end
  end

  def test_block_arg
    source = parse_ruby(<<EOF)
# @type method f: () { (any) -> any } -> any
def f(&block)
end
EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = new_subtyping_checker(<<-EOF)
    EOF
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
                                        block_context: nil,
                                        self_type: Types::Name.new_instance(name: "::Object"),
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)
    construction.synthesize(source.node)

    assert_empty typing.errors
  end

  def test_and_or
    source = parse_ruby(<<EOF)
a = true && false
b = false || true
EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = new_subtyping_checker(<<-EOF)
    EOF
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
                                        block_context: nil,
                                        self_type: Types::Name.new_instance(name: "::Object"),
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)
    construction.synthesize(source.node)

    assert_empty typing.errors

    assert_equal Types::Name.new_interface(name: :_Boolean), type_env.lvar_types[:a]
    assert_equal Types::Name.new_interface(name: :_Boolean), type_env.lvar_types[:b]
  end

  def test_empty_body_method
    source = parse_ruby(<<EOF)
class EmptyBodyMethod
  def foo
  end
end
EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = new_subtyping_checker(<<-EOF)
class EmptyBodyMethod
  def foo: () -> String
end
    EOF
    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
                                        block_context: nil,
                                        self_type: Types::Name.new_instance(name: "::Object"),
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)
    construction.synthesize(source.node)

    refute_empty typing.errors
  end

  def test_nil_reject
    source = parse_ruby(<<EOF)
# @type var x: Integer?
x = "x"
EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = new_subtyping_checker()

    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
                                        block_context: nil,
                                        self_type: Types::Name.new_instance(name: "::Object"),
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)
    construction.synthesize(source.node)

    assert_equal 1, typing.errors.size
    typing.errors[0].yield_self do |error|
      assert_instance_of Steep::Errors::IncompatibleAssignment, error
    end
  end

  def test_nil_method
    source = parse_ruby(<<EOF)
nil.class
nil.no_such_method
EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = new_subtyping_checker()

    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
                                        block_context: nil,
                                        self_type: Types::Name.new_instance(name: "::Object"),
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)
    construction.synthesize(source.node)

    assert_equal 1, typing.errors.size
    typing.errors[0].yield_self do |error|
      assert_instance_of Steep::Errors::NoMethod, error
      assert_equal :no_such_method, error.method
    end
  end

  def test_optional_method
    source = parse_ruby(<<EOF)
# @type var x: Integer?
x = 3
x.to_s
x.no_such_method
EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = new_subtyping_checker()

    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
                                        block_context: nil,
                                        self_type: Types::Name.new_instance(name: "::Object"),
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)
    construction.synthesize(source.node)

    assert_equal 1, typing.errors.size
    typing.errors[0].yield_self do |error|
      assert_instance_of Steep::Errors::NoMethod, error
      assert_equal :no_such_method, error.method
    end
  end

  def test_literal
    source = parse_ruby(<<EOF)
# @type var x: 123
x = 123
a = ClassWithLiteralArg.new.foo(x)
b = ClassWithLiteralArg.new.foo(123)
c = ClassWithLiteralArg.new.foo(1234)
EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = new_subtyping_checker(<<-EOF)
class ClassWithLiteralArg
  def foo: (123) -> "foo"
         | (Integer) -> :bar
end
    EOF

    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
                                        block_context: nil,
                                        self_type: Types::Name.new_instance(name: "::Object"),
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)
    construction.synthesize(source.node)

    assert_empty typing.errors

    assert_equal parse_type('"foo"'), type_env.lvar_types[:a]
    assert_equal parse_type('"foo"'), type_env.lvar_types[:b]
    assert_equal parse_type(':bar'), type_env.lvar_types[:c]
  end

  def test_literal2
    source = parse_ruby(<<EOF)
# @type var x: 123
x = 123
x + 123

# @type var y: "foo"
y = "foo"
y + "bar"
EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)
    checker = new_subtyping_checker()

    const_env = ConstantEnv.new(builder: checker.builder, current_namespace: nil)
    type_env = TypeEnv.build(annotations: annotations,
                             subtyping: checker,
                             const_env: const_env,
                             signatures: checker.builder.signatures)

    construction = TypeConstruction.new(checker: checker,
                                        source: source,
                                        annotations: annotations,
                                        type_env: type_env,
                                        block_context: nil,
                                        self_type: Types::Name.new_instance(name: "::Object"),
                                        method_context: nil,
                                        typing: typing,
                                        module_context: nil,
                                        break_context: nil)
    construction.synthesize(source.node)

    assert_empty typing.errors
  end
end
