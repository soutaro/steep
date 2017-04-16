require "test_helper"

class TypeConstructionTest < Minitest::Test
  Source = Steep::Source
  TypeAssignability = Steep::TypeAssignability
  Typing = Steep::Typing
  TypeConstruction = Steep::TypeConstruction
  Parser = Steep::Parser
  TypeEnv = Steep::TypeEnv
  Types = Steep::Types

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
      EOS
      interfaces.each do |interface|
        assignability.add_interface interface
      end
    end
  end

  def test_lvar_with_annotation
    source = ruby(<<-EOF)
# @type x: A
x = nil
    EOF

    typing = Typing.new
    env = TypeEnv.from_annotations(source.annotations(block: source.node), env: {})

    construction = TypeConstruction.new(assignability: assignability, source: source, env: env, typing: typing)
    construction.run(source.node)

    assert_equal Types::Name.new(name: :A), typing.type_of(node: source.node)
    assert_empty typing.errors
  end

  def test_lvar_with_annotation_type_check
    source = ruby(<<-EOF)
# @type x: B
# @type z: A
x = nil
z = x
    EOF

    typing = Typing.new
    env = TypeEnv.from_annotations(source.annotations(block: source.node) || [], env: {})

    construction = TypeConstruction.new(assignability: assignability, source: source, env: env, typing: typing)
    construction.run(source.node)

    assert_equal Types::Name.new(name: :A), typing.type_of(node: source.node)

    assert_equal 1, typing.errors.size
    assert_incompatible_assignment typing.errors[0],
                                   lhs_type: Types::Name.new(name: :A),
                                   rhs_type: Types::Name.new(name: :B) do |error|
      assert_equal :lvasgn, error.node.type
      assert_equal :z, error.node.children[0]
    end
  end

  def test_lvar_without_annotation
    source = ruby(<<-EOF)
x = 1
z = x
    EOF

    typing = Typing.new
    env = TypeEnv.from_annotations(source.annotations(block: source.node) || [], env: {})

    construction = TypeConstruction.new(assignability: assignability, source: source, env: env, typing: typing)
    construction.run(source.node)

    assert_equal Types::Any.new, typing.type_of(node: source.node)
    assert_empty typing.errors
  end

  def test_lvar_without_annotation_inference
    source = ruby(<<-EOF)
# @type x: A
x = nil
z = x
    EOF

    typing = Typing.new
    env = TypeEnv.from_annotations(source.annotations(block: source.node) || [], env: {})

    construction = TypeConstruction.new(assignability: assignability, source: source, env: env, typing: typing)
    construction.run(source.node)

    assert_equal Types::Name.new(name: :A), typing.type_of(node: source.node)
    assert_empty typing.errors
  end

  def test_method_call
    source = ruby(<<-EOF)
# @type x: C
x = nil
x.f
    EOF

    typing = Typing.new
    env = TypeEnv.from_annotations(source.annotations(block: source.node), env: {})

    construction = TypeConstruction.new(assignability: assignability, source: source, env: env, typing: typing)
    construction.run(source.node)

    assert_equal Types::Name.new(name: :A), typing.type_of(node: source.node)
    assert_empty typing.errors
  end

  def test_method_call_with_argument
    source = ruby(<<-EOF)
# @type x: C
# @type y: A
x = nil
y = nil
x.g(y)
    EOF

    typing = Typing.new
    env = TypeEnv.from_annotations(source.annotations(block: source.node), env: {})

    construction = TypeConstruction.new(assignability: assignability, source: source, env: env, typing: typing)
    construction.run(source.node)

    assert_equal Types::Name.new(name: :B), typing.type_of(node: source.node)
    assert_empty typing.errors
  end

  def test_method_call_incompatible_argument_type
    source = ruby(<<-EOF)
# @type x: C
# @type y: B
x = nil
y = nil
x.g(y)
    EOF

    typing = Typing.new
    env = TypeEnv.from_annotations(source.annotations(block: source.node) || nil, env: {})

    construction = TypeConstruction.new(assignability: assignability, source: source, env: env, typing: typing)
    construction.run(source.node)

    assert_equal Types::Name.new(name: :B), typing.type_of(node: source.node)

    assert_equal 1, typing.errors.size
    assert_invalid_argument_error typing.errors[0],
                                  expected_type: Types::Name.new(name: :A),
                                  actual_type: Types::Name.new(name: :B)
  end

  def test_method_call_no_error_if_any
    source = ruby(<<-EOF)
x = nil
x.no_such_method
    EOF

    typing = Typing.new
    env = TypeEnv.from_annotations(source.annotations(block: source.node) || [], env: {})

    construction = TypeConstruction.new(assignability: assignability, source: source, env: env, typing: typing)
    construction.run(source.node)

    assert_equal Types::Any.new, typing.type_of(node: source.node)
    assert_empty typing.errors
  end

  def test_method_call_no_method_error
    source = ruby(<<-EOF)
# @type x: C
x = nil
x.no_such_method
    EOF

    typing = Typing.new
    env = TypeEnv.from_annotations(source.annotations(block: source.node) || [], env: {})

    construction = TypeConstruction.new(assignability: assignability, source: source, env: env, typing: typing)
    construction.run(source.node)

    assert_equal Types::Any.new, typing.type_of(node: source.node)

    assert_equal 1, typing.errors.size
    assert_no_method_error typing.errors.first, method: :no_such_method, type: Types::Name.new(name: :C)
  end

  def test_method_call_missing_argument
    source = ruby(<<-EOF)
# @type x: A
# @type a: C
a = nil
x = nil
a.g()
    EOF

    typing = Typing.new
    env = TypeEnv.from_annotations(source.annotations(block: source.node) || [], env: {})

    construction = TypeConstruction.new(assignability: assignability, source: source, env: env, typing: typing)
    construction.run(source.node)

    assert_equal Types::Name.new(name: :B), typing.type_of(node: source.node)

    assert_equal 1, typing.errors.size
    assert_expected_argument_missing typing.errors.first, index: 0
  end

  def test_method_call_extra_args
    source = ruby(<<-EOF)
# @type x: A
# @type a: C
a = nil
x = nil
a.g(nil, nil, nil)
    EOF

    typing = Typing.new
    env = TypeEnv.from_annotations(source.annotations(block: source.node) || [], env: {})

    construction = TypeConstruction.new(assignability: assignability, source: source, env: env, typing: typing)
    construction.run(source.node)

    assert_equal Types::Name.new(name: :B), typing.type_of(node: source.node)

    assert_equal 1, typing.errors.size
    assert_extra_argument_given typing.errors.first, index: 2
  end

  def test_keyword_call
    source = ruby(<<-EOF)
# @type x: C
# @type a: A
# @type b: B
x = nil
a = nil
b = nil
x.h(a: a, b: b)
    EOF

    typing = Typing.new
    env = TypeEnv.from_annotations(source.annotations(block: source.node) || [], env: {})

    construction = TypeConstruction.new(assignability: assignability, source: source, env: env, typing: typing)
    construction.run(source.node)

    assert_equal Types::Name.new(name: :C), typing.type_of(node: source.node)
    assert_empty typing.errors
  end

  def test_keyword_missing
    source = ruby(<<-EOF)
# @type x: C
x = nil
x.h()
    EOF

    typing = Typing.new
    env = TypeEnv.from_annotations(source.annotations(block: source.node) || [], env: {})

    construction = TypeConstruction.new(assignability: assignability, source: source, env: env, typing: typing)
    construction.run(source.node)

    assert_equal Types::Name.new(name: :C), typing.type_of(node: source.node)

    assert_equal 1, typing.errors.size
    assert_expected_keyword_missing typing.errors[0], keyword: :a
  end

  def test_extra_keyword_given
    source = ruby(<<-EOF)
# @type x: C
x = nil
x.h(a: nil, b: nil, c: nil)
    EOF

    typing = Typing.new
    env = TypeEnv.from_annotations(source.annotations(block: source.node) || [], env: {})

    construction = TypeConstruction.new(assignability: assignability, source: source, env: env, typing: typing)
    construction.run(source.node)

    assert_equal Types::Name.new(name: :C), typing.type_of(node: source.node)

    assert_equal 1, typing.errors.size
    assert_extra_keyword_given typing.errors[0], keyword: :c
  end

  def test_keyword_typecheck
    source = ruby(<<-EOF)
# @type x: C
# @type y: B
x = nil
y = nil
x.h(a: y)
    EOF

    typing = Typing.new
    env = TypeEnv.from_annotations(source.annotations(block: source.node) || [], env: {})

    construction = TypeConstruction.new(assignability: assignability, source: source, env: env, typing: typing)
    construction.run(source.node)

    assert_equal Types::Name.new(name: :C), typing.type_of(node: source.node)

    assert_equal 1, typing.errors.size
    assert_invalid_argument_error typing.errors[0], expected_type: Types::Name.new(name: :A), actual_type: Types::Name.new(name: :B)
  end

  def arguments(ruby)
    ::Parser::CurrentRuby.parse(ruby).children.drop(2)
  end

  def test_argument_pairs
    params = Types::Interface::Params.empty.with(required: [Types::Name.new(name: :A)],
                                                 optional: [Types::Name.new(name: :B)],
                                                 rest: Types::Name.new(name: :C),
                                                 required_keywords: { d: Types::Name.new(name: :D) },
                                                 optional_keywords: { e: Types::Name.new(name: :E) },
                                                 rest_keywords: Types::Name.new(name: :F))
    arguments = arguments("f(a, b, c, d: d, e: e, f: f)")

    assert_equal [
                   [Types::Name.new(name: :A), arguments[0]],
                   [Types::Name.new(name: :B), arguments[1]],
                   [Types::Name.new(name: :C), arguments[2]],
                   [Types::Name.new(name: :D), arguments[3].children[0].children[1]],
                   [Types::Name.new(name: :E), arguments[3].children[1].children[1]],
                   [Types::Name.new(name: :F), arguments[3].children[2].children[1]]
                 ], TypeConstruction.argument_typing_pairs(params: params, arguments: arguments)
  end

  def test_argument_pairs_rest_keywords
    params = Types::Interface::Params.empty.with(required: [Types::Name.new(name: :A)],
                                                 optional: [Types::Name.new(name: :B)],
                                                 rest: Types::Name.new(name: :C),
                                                 required_keywords: { d: Types::Name.new(name: :D) },
                                                 optional_keywords: { e: Types::Name.new(name: :E) },
                                                 rest_keywords: Types::Name.new(name: :F))
    arguments = arguments("f(a, b, c, d: d, e: e, f: f)")

    assert_equal [
                   [Types::Name.new(name: :A), arguments[0]],
                   [Types::Name.new(name: :B), arguments[1]],
                   [Types::Name.new(name: :C), arguments[2]],
                   [Types::Name.new(name: :D), arguments[3].children[0].children[1]],
                   [Types::Name.new(name: :E), arguments[3].children[1].children[1]],
                   [Types::Name.new(name: :F), arguments[3].children[2].children[1]]
                 ], TypeConstruction.argument_typing_pairs(params: params, arguments: arguments)
  end

  def test_argument_pairs_required
    params = Types::Interface::Params.empty.with(required: [Types::Name.new(name: :A)],
                                                 optional: [Types::Name.new(name: :B)],
                                                 rest: Types::Name.new(name: :C))
    arguments = arguments("f(a, b, c)")

    assert_equal [
                   [Types::Name.new(name: :A), arguments[0]],
                   [Types::Name.new(name: :B), arguments[1]],
                   [Types::Name.new(name: :C), arguments[2]],
                 ], TypeConstruction.argument_typing_pairs(params: params, arguments: arguments)
  end

  def test_argument_pairs_hash
    params = Types::Interface::Params.empty.with(required: [Types::Name.new(name: :A)],
                                                 optional: [Types::Name.new(name: :B)],
                                                 rest: Types::Name.new(name: :C))
    arguments = arguments("f(a, b, c, d: d)")

    assert_equal [
                   [Types::Name.new(name: :A), arguments[0]],
                   [Types::Name.new(name: :B), arguments[1]],
                   [Types::Name.new(name: :C), arguments[2]],
                   [Types::Name.new(name: :C), arguments[3]]
                 ], TypeConstruction.argument_typing_pairs(params: params, arguments: arguments)
  end

  def test_argument_keywords
    params = Types::Interface::Params.empty.with(required_keywords: { d: Types::Name.new(name: :D) },
                                                 optional_keywords: { e: Types::Name.new(name: :E) },
                                                 rest_keywords: Types::Name.new(name: :F))

    arguments = arguments("f(d: d, e: e, f: f)")

    assert_equal [
                   [Types::Name.new(name: :D), arguments[0].children[0].children[1]],
                   [Types::Name.new(name: :E), arguments[0].children[1].children[1]],
                   [Types::Name.new(name: :F), arguments[0].children[2].children[1]],
                 ], TypeConstruction.argument_typing_pairs(params: params, arguments: arguments)
  end

  def test_argument_hash_not_keywords
    params = Types::Interface::Params.empty.with(required: [Types::Name.new(name: :A)])

    arguments = arguments("f(d: d, e: e, f: f)")

    assert_equal [
                   [Types::Name.new(name: :A), arguments[0]]
                 ], TypeConstruction.argument_typing_pairs(params: params, arguments: arguments)
  end
end
