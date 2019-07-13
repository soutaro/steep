require_relative "test_helper"

class ArgsTest < Minitest::Test
  include TestHelper
  include FactoryHelper

  SendArgs = Steep::TypeInference::SendArgs
  Params = Steep::Interface::Params
  Types = Steep::AST::Types
  AST = Steep::AST

  include Minitest::Hooks

  def around
    with_factory do
      super
    end
  end

  def test_1
    nodes = parse_ruby("foo(1, 2, *rest, k1: foo(), k2: bar(), **k3, &proc)").node.children.drop(2)
    args = SendArgs.from_nodes(nodes)

    assert_equal [nodes[0], nodes[1], nodes[2], nodes[3]], args.args
    assert_equal nodes[4], args.block_pass_arg
  end

  def test_2
    nodes = parse_ruby("foo({ k1: foo(), k2: bar() }, **k3)").node.children.drop(2)
    args = SendArgs.from_nodes(nodes)

    assert_equal [nodes[0], nodes[1]], args.args
  end

  def test_3
    nodes = parse_ruby("foo({ 'k1' => foo(), k2: bar() })").node.children.drop(2)
    args = SendArgs.from_nodes(nodes)

    assert_equal [nodes[0]], args.args
  end

  def test_zip_0
    params = Params.new(
      required: [parse_type("Integer"), parse_type("String")],
      optional: [],
      rest: nil,
      required_keywords: {},
      optional_keywords: {},
      rest_keywords: nil
    )

    SendArgs.from_nodes(parse_ruby("foo(:a, :b)").node.children.drop(2)).yield_self do |args|
      pairs, *rest = args.zips(params, nil)

      assert_empty rest

      assert_equal [
                     [parse_ruby(":a").node, parse_type("Integer")],
                     [parse_ruby(":b").node, parse_type("String")]
                   ], pairs
    end

    SendArgs.from_nodes(parse_ruby("foo(:a)").node.children.drop(2)).yield_self do |args|
      zips = args.zips(params, nil)
      assert_empty zips
    end

    SendArgs.from_nodes(parse_ruby("foo(1, 2, 3)").node.children.drop(2)).yield_self do |args|
      zips = args.zips(params, nil)
      assert_empty zips
    end
  end

  def test_zip_1
    params = Params.new(
      required: [],
      optional: [parse_type("Integer"), parse_type("String")],
      rest: nil,
      required_keywords: {},
      optional_keywords: {},
      rest_keywords: nil
    )

    SendArgs.from_nodes(parse_ruby("foo(:a)").node.children.drop(2)).yield_self do |args|
      pairs, *rest = args.zips(params, nil)
      assert_empty rest
      assert_equal [[parse_ruby(":a").node, parse_type("Integer")]], pairs
    end

    SendArgs.from_nodes(parse_ruby("foo()").node.children.drop(2)).yield_self do |args|
      pairs, *rest = args.zips(params, nil)
      assert_empty rest
      assert_empty pairs
    end

    SendArgs.from_nodes(parse_ruby("foo(1, 2, 3)").node.children.drop(2)).yield_self do |args|
      zips = args.zips(params, nil)
      assert_empty zips
    end
  end

  def test_zip_2
    params = Params.new(
      required: [parse_type("Integer")],
      optional: [],
      rest: nil,
      required_keywords: { name: parse_type("String") },
      optional_keywords: {},
      rest_keywords: nil
    )

    SendArgs.from_nodes(parse_ruby("foo(:a, name: 'hello')").node.children.drop(2)).yield_self do |args|
      pairs, *rest = args.zips(params, nil)
      assert_empty rest
      assert_equal [
                     [parse_ruby(":a").node, parse_type("Integer")],
                     parse_ruby("{ name: 'hello' }").node
                   ], pairs
    end

    SendArgs.from_nodes(parse_ruby("foo(:a)").node.children.drop(2)).yield_self do |args|
      zips = args.zips(params, nil)
      assert_empty zips
    end

    SendArgs.from_nodes(parse_ruby("foo(1, 2)").node.children.drop(2)).yield_self do |args|
      pairs, *rest = args.zips(params, nil)
      assert_empty rest
      assert_equal [
                     [parse_ruby("1").node, parse_type("Integer")],
                     parse_ruby("2").node
                   ], pairs
    end
  end

  def test_zip_3
    params = Params.new(
      required: [],
      optional: [parse_type("Symbol")],
      rest: nil,
      required_keywords: {},
      optional_keywords: { name: parse_type("String") },
      rest_keywords: nil
    )

    SendArgs.from_nodes(parse_ruby("foo(:a, name: 'hello')").node.children.drop(2)).yield_self do |args|
      pairs, *rest = args.zips(params, nil)
      assert_empty rest
      assert_equal [
                     [parse_ruby(":a").node, parse_type("Symbol")],
                     parse_ruby("{ name: 'hello' }").node
                   ], pairs
    end

    SendArgs.from_nodes(parse_ruby("foo(:a)").node.children.drop(2)).yield_self do |args|
      pairs1, pairs2, *rest = args.zips(params, nil)

      assert_empty rest
      assert_equal [
                     parse_ruby(":a").node
                   ], pairs1
      assert_equal [
                     [parse_ruby(":a").node, parse_type("Symbol")]
                   ], pairs2
    end
  end

  def test_zip_4
    params = Params.new(
      required: [],
      optional: [],
      rest: parse_type("Integer"),
      required_keywords: {},
      optional_keywords: { name: parse_type("String") },
      rest_keywords: nil
    )

    SendArgs.from_nodes(parse_ruby("foo(:a, name: 'hello')").node.children.drop(2)).yield_self do |args|
      pairs1, pairs2, *rest = args.zips(params, nil)
      assert_empty rest
      assert_equal [
                     [parse_ruby(":a").node, parse_type("Integer")],
                     parse_ruby("{ name: 'hello' }").node
                   ], pairs1
      assert_equal [
                     [parse_ruby(":a").node, parse_type("Integer")],
                     [parse_ruby("{ name: 'hello' }").node, parse_type("Integer")]
                   ], pairs2
    end

    SendArgs.from_nodes(parse_ruby("foo()").node.children.drop(2)).yield_self do |args|
      pairs, *rest = args.zips(params, nil)
      assert_empty rest
      assert_equal [], pairs
    end
  end

  def params(ruby)
    parse_ruby(ruby).node.children.drop(2)
  end

  def test_zip_5
    params = Params.new(
      required: [parse_type("String")],
      optional: [parse_type("Symbol"), parse_type("Integer")],
      rest: parse_type("Integer"),
      required_keywords: {},
      optional_keywords: {},
      rest_keywords: nil
    )

    SendArgs.from_nodes(params("foo(1, 2, 3, *args)")).yield_self do |args|
      pairs, *rest = args.zips(params, nil)

      assert_empty rest

      assert_equal [
                     [parse_ruby("1").node, parse_type("String")],
                     [parse_ruby("2").node, parse_type("Symbol")],
                     [parse_ruby("3").node, parse_type("Integer")],
                     [args.args[3], parse_type("::Array[Integer]")]
                   ], pairs

    end

    SendArgs.from_nodes(params("foo(1, 2, *args)")).yield_self do |args|
      pairs, *rest = args.zips(params, nil)

      assert_empty rest

      assert_equal [
                     [parse_ruby("1").node, parse_type("String")],
                     [parse_ruby("2").node, parse_type("Symbol")],
                     [args.args[2], parse_type("::Array[Integer]")]
                   ], pairs

    end

    SendArgs.from_nodes(params("foo(1, *args)")).yield_self do |args|
      pairs, *rest = args.zips(params, nil)

      assert_empty rest

      assert_equal [
                     [parse_ruby("1").node, parse_type("String")],
                     [args.args[1],
                      AST::Types::Intersection.build(types: [
                        parse_type("::Array[Symbol]"),
                        parse_type("::Array[Integer]")
                      ])
                     ]
                   ], pairs

    end

    SendArgs.from_nodes(params("foo(*args)")).yield_self do |args|
      pairs, *rest = args.zips(params, nil)

      assert_empty rest
      assert_nil pairs
    end
  end

  def test_zip_6
    params = Params.new(
      required: [],
      optional: [],
      rest: parse_type("Integer"),
      required_keywords: { name: parse_type("String") },
      optional_keywords: {},
      rest_keywords: nil
    )

    SendArgs.from_nodes(params("foo(*args, name: 1)")).yield_self do |args|
      pairs, *rest = args.zips(params, nil)

      assert_empty rest

      assert_equal [
                     [args.args[0], parse_type("::Array[Integer]")],
                     args.args[1]
                   ], pairs
    end

    SendArgs.from_nodes(params("foo(*args)")).yield_self do |args|
      pairs, *rest = args.zips(params, nil)

      assert_empty rest
      assert_nil pairs
    end
  end

  def test_zip_7
    params = Params.new(
      required: [],
      optional: [],
      rest: parse_type("Integer"),
      required_keywords: {},
      optional_keywords: { foo: parse_type("bar") },
      rest_keywords: nil
    )

    SendArgs.from_nodes(params("foo(*args, name: 1)")).yield_self do |args|
      pairs1, pairs2, *rest = args.zips(params, nil)

      assert_empty rest

      assert_equal [
                     [args.args[0], parse_type("::Array[Integer]")],
                     args.args[1]
                   ], pairs1

      assert_equal [
                     [args.args[0], parse_type("::Array[Integer]")],
                     [args.args[1], parse_type("Integer")]
                   ], pairs2
    end

    SendArgs.from_nodes(params("foo(*args)")).yield_self do |args|
      pairs, *rest = args.zips(params, nil)

      assert_empty rest
      assert_equal [
                     [args.args[0], parse_type("::Array[Integer]")]
                   ], pairs
    end
  end
end
