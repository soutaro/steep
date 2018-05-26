require_relative "test_helper"

class ArgsTest < Minitest::Test
  include TestHelper

  SendArgs = Steep::TypeInference::SendArgs
  Params = Steep::Interface::Params
  Types = Steep::AST::Types

  def test_1
    nodes = parse_ruby("foo(1, 2, *rest, k1: foo(), k2: bar(), **k3)").node.children.drop(2)
    args = SendArgs.from_nodes(nodes)

    assert_equal [nodes[0], nodes[1], nodes[2]], args.args
    assert_equal nodes[3], args.kw_args
  end

  def test_2
    nodes = parse_ruby("foo({ k1: foo(), k2: bar() }, **k3)").node.children.drop(2)
    args = SendArgs.from_nodes(nodes)

    assert_equal [nodes[0]], args.args
    assert_equal nodes[1], args.kw_args
  end

  def test_3
    nodes = parse_ruby("foo({ 'k1' => foo(), k2: bar() })").node.children.drop(2)
    args = SendArgs.from_nodes(nodes)

    assert_equal [nodes[0]], args.args
    assert_nil args.kw_args
  end

  def test_zip1
    params = Params.new(
      required: [Types::Name.new_instance(name: :Integer)],
      optional: [Types::Name.new_instance(name: :String)],
      rest: nil,
      required_keywords: {},
      optional_keywords: {},
      rest_keywords: nil
    )

    args = SendArgs.from_nodes(parse_ruby("foo(:a, :b)").node.children.drop(2))

    pairs = args.zip(params)

    refute_nil pairs
    assert_equal Set.new([
                           [parse_ruby(":a").node, Types::Name.new_instance(name: :Integer)],
                           [parse_ruby(":b").node, Types::Name.new_instance(name: :String)]
                         ]),
                 pairs
  end

  def test_zip2
    params = Params.new(
      required: [Types::Name.new_instance(name: :Integer),
                 Types::Name.new_instance(name: :String)],
      optional: [],
      rest: nil,
      required_keywords: {},
      optional_keywords: {},
      rest_keywords: nil
    )

    SendArgs.from_nodes(parse_ruby("foo(:a, x: 1)").node.children.drop(2)).yield_self do |args|
      pairs = args.zip(params)

      refute_nil pairs
      assert_equal Set.new([
                             [args.args[0], Types::Name.new_instance(name: :Integer)],
                             [args.kw_args, Types::Name.new_instance(name: :String)],
                           ]),
                   pairs
    end

    SendArgs.from_nodes(parse_ruby("foo(*args)").node.children.drop(2)).yield_self do |args|
      pairs = args.zip(params)

      refute_nil pairs
      assert_equal Set.new([
                             [args.args[0],
                              Types::Name.new_instance(name: "::Array",
                                                       args: [
                                                         Types::Union.build(types: [
                                                           Types::Name.new_instance(name: :Integer),
                                                           Types::Name.new_instance(name: :String),
                                                         ])
                                                       ])]
                           ]),
                   pairs
    end
  end

  def test_zip3
    params = Params.new(
      required: [],
      optional: [],
      rest: nil,
      required_keywords: { foo: Types::Name.new_instance(name: :Object) },
      optional_keywords: { bar: Types::Name.new_instance(name: :Integer) },
      rest_keywords: nil
    )

    SendArgs.from_nodes(parse_ruby("foo(foo: 1)").node.children.drop(2)).yield_self do |args|
      pairs = args.zip(params)

      refute_nil pairs
      assert_equal Set.new([
                             [parse_ruby("1").node, Types::Name.new_instance(name: :Object)]
                           ]),
                   pairs
    end

    SendArgs.from_nodes(parse_ruby("foo(foo: 1, bar: 2)").node.children.drop(2)).yield_self do |args|
      pairs = args.zip(params)

      refute_nil pairs
      assert_equal Set.new([
                             [parse_ruby("1").node, Types::Name.new_instance(name: :Object)],
                             [parse_ruby("2").node, Types::Name.new_instance(name: :Integer)]
                           ]),
                   pairs
    end

    SendArgs.from_nodes(parse_ruby("foo(bar: 2)").node.children.drop(2)).yield_self do |args|
      pairs = args.zip(params)

      assert_nil pairs
    end

    SendArgs.from_nodes(parse_ruby("foo(foo: 2, baz: 3)").node.children.drop(2)).yield_self do |args|
      pairs = args.zip(params)

      assert_nil pairs
    end
  end

  def test_zip4
    params = Params.new(
      required: [],
      optional: [],
      rest: nil,
      required_keywords: { foo: Types::Name.new_instance(name: :Object) },
      optional_keywords: { bar: Types::Name.new_instance(name: :Integer) },
      rest_keywords: Types::Name.new_instance(name: :String)
    )

    SendArgs.from_nodes(parse_ruby("foo(foo: 1)").node.children.drop(2)).yield_self do |args|
      pairs = args.zip(params)

      refute_nil pairs
      assert_equal Set.new([
                             [parse_ruby("1").node, Types::Name.new_instance(name: :Object)]
                           ]),
                   pairs
    end

    SendArgs.from_nodes(parse_ruby("foo(foo: 1, baz: 3, **params)").node.children.drop(2)).yield_self do |args|
      pairs = args.zip(params)

      refute_nil pairs
      assert_equal Set.new([
                             [parse_ruby("1").node, Types::Name.new_instance(name: :Object)],
                             [parse_ruby("3").node, Types::Name.new_instance(name: :String)],
                             [args.kw_args, Types::Name.new_instance(name: "::Hash",
                                                                     args: [
                                                                       Types::Name.new_instance(name: "::Symbol"),
                                                                       Types::Union.build(types: [
                                                                         Types::Name.new_instance(name: :String),
                                                                         Types::Name.new_instance(name: :Integer)
                                                                       ])
                                                                     ])]
                           ]),
                   pairs
    end
  end

  def test_zip5
    params = Params.new(
      required: [Types::Name.new_instance(name: :Integer)],
      optional: [Types::Name.new_instance(name: :String)],
      rest: Types::Name.new_instance(name: :Object),
      required_keywords: {},
      optional_keywords: {},
      rest_keywords: nil
    )

    SendArgs.from_nodes(parse_ruby("foo(:a, :b)").node.children.drop(2)).yield_self do |args|
      pairs = args.zip(params)

      refute_nil pairs
      assert_equal Set.new([
                             [parse_ruby(":a").node, Types::Name.new_instance(name: :Integer)],
                             [parse_ruby(":b").node, Types::Name.new_instance(name: :String)]
                           ]),
                   pairs
    end

    SendArgs.from_nodes(parse_ruby("foo(:a, :b, :c)").node.children.drop(2)).yield_self do |args|
      pairs = args.zip(params)

      refute_nil pairs
      assert_equal Set.new([
                             [parse_ruby(":a").node, Types::Name.new_instance(name: :Integer)],
                             [parse_ruby(":b").node, Types::Name.new_instance(name: :String)],
                             [parse_ruby(":c").node, Types::Name.new_instance(name: :Object)]
                           ]),
                   pairs
    end

    SendArgs.from_nodes(parse_ruby("foo(:a, :b, :c, *d)").node.children.drop(2)).yield_self do |args|
      pairs = args.zip(params)

      refute_nil pairs
      assert_equal Set.new([
                             [parse_ruby(":a").node, Types::Name.new_instance(name: :Integer)],
                             [parse_ruby(":b").node, Types::Name.new_instance(name: :String)],
                             [parse_ruby(":c").node, Types::Name.new_instance(name: :Object)],
                             [args.args[3], Types::Name.new_instance(name: "::Array",
                                                                     args: [
                                                                       Types::Name.new_instance(name: :Object)
                                                                     ])]
                           ]),
                   pairs
    end

    SendArgs.from_nodes(parse_ruby("foo(:a, :b, :c, *d, :e)").node.children.drop(2)).yield_self do |args|
      pairs = args.zip(params)

      refute_nil pairs
      assert_equal Set.new([
                             [parse_ruby(":a").node, Types::Name.new_instance(name: :Integer)],
                             [parse_ruby(":b").node, Types::Name.new_instance(name: :String)],
                             [parse_ruby(":c").node, Types::Name.new_instance(name: :Object)],
                             [args.args[3], Types::Name.new_instance(name: "::Array",
                                                                     args: [
                                                                       Types::Name.new_instance(name: :Object)
                                                                     ])],
                             [parse_ruby(":e").node, Types::Name.new_instance(name: :Object)],
                           ]),
                   pairs
    end

    SendArgs.from_nodes(parse_ruby("foo(:a, *b, :c)").node.children.drop(2)).yield_self do |args|
      pairs = args.zip(params)

      refute_nil pairs
      assert_equal Set.new([
                             [parse_ruby(":a").node, Types::Name.new_instance(name: :Integer)],
                             [args.args[1],
                              Types::Name.new_instance(name: "::Array",
                                                       args: [
                                                         Types::Union.build(types: [
                                                           Types::Name.new_instance(name: :Object),
                                                           Types::Name.new_instance(name: :String),
                                                         ])
                                                       ])],
                             [parse_ruby(":c").node,
                              Types::Union.build(types: [
                                Types::Name.new_instance(name: :Object),
                                Types::Name.new_instance(name: :String),
                              ])]
                           ]),
                   pairs
    end

    SendArgs.from_nodes(parse_ruby("foo(*a, :b, *c)").node.children.drop(2)).yield_self do |args|
      pairs = args.zip(params)

      refute_nil pairs
      assert_equal Set.new([
                             [args.args[0],
                              Types::Name.new_instance(name: "::Array",
                                                       args: [
                                                         Types::Union.build(types: [
                                                           Types::Name.new_instance(name: :Integer),
                                                           Types::Name.new_instance(name: :Object),
                                                           Types::Name.new_instance(name: :String),
                                                         ])
                                                       ])],
                             [args.args[1],
                              Types::Union.build(types: [
                                Types::Name.new_instance(name: :Integer),
                                Types::Name.new_instance(name: :Object),
                                Types::Name.new_instance(name: :String),
                              ])],
                             [args.args[2],
                              Types::Name.new_instance(name: "::Array",
                                                       args: [
                                                         Types::Union.build(types: [
                                                           Types::Name.new_instance(name: :Integer),
                                                           Types::Name.new_instance(name: :Object),
                                                           Types::Name.new_instance(name: :String),
                                                         ])
                                                       ])],
                           ]),
                   pairs
    end
  end
end
