require_relative "test_helper"

class ArgsTest < Minitest::Test
  include TestHelper

  SendArgs = Steep::TypeInference::SendArgs
  Params = Steep::Interface::Params
  Types = Steep::AST::Types

  def test_1
    nodes = parse_ruby("foo(1, 2, *rest, k1: foo(), k2: bar(), **k3)").node.children.drop(2)
    args = SendArgs.from_nodes(nodes)

    assert_equal [parse_ruby("1").node, parse_ruby("2").node], args.args
    assert_equal parse_ruby("rest").node, args.rest
    assert_equal({ k1: parse_ruby("foo()").node,
                   k2: parse_ruby("bar()").node }, args.kw_args)
    assert_equal parse_ruby("k3").node, args.rest_kw
  end

  def test_2
    nodes = parse_ruby("foo({ k1: foo(), k2: bar() }, **k3)").node.children.drop(2)
    args = SendArgs.from_nodes(nodes)

    assert_equal [parse_ruby("{ k1: foo(), k2: bar() }").node], args.args
    assert_nil args.rest
    assert_empty args.kw_args
    assert_equal parse_ruby("k3").node, args.rest_kw
  end

  def test_3
    nodes = parse_ruby("foo({ k1: foo(), k2: bar() })").node.children.drop(2)
    args = SendArgs.from_nodes(nodes)

    assert_empty args.args
    assert_nil args.rest
    assert_equal({ k1: parse_ruby("foo()").node,
                   k2: parse_ruby("bar()").node }, args.kw_args)
    assert_nil args.rest_kw
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
    assert_equal [[parse_ruby(":a").node, Types::Name.new_instance(name: :Integer)],
                  [parse_ruby(":b").node, Types::Name.new_instance(name: :String)]], pairs
  end

  def test_zip2
    params = Params.new(
      required: [Types::Name.new_instance(name: :Integer)],
      optional: [Types::Name.new_instance(name: :String)],
      rest: nil,
      required_keywords: {},
      optional_keywords: {},
      rest_keywords: nil
    )

    args = SendArgs.from_nodes(parse_ruby("foo(:a)").node.children.drop(2))

    pairs = args.zip(params)

    refute_nil pairs
    assert_equal [[parse_ruby(":a").node, Types::Name.new_instance(name: :Integer)]], pairs
  end

  def test_zip3
    params = Params.new(
      required: [Types::Name.new_instance(name: :Integer)],
      optional: [Types::Name.new_instance(name: :String)],
      rest: nil,
      required_keywords: {},
      optional_keywords: {},
      rest_keywords: nil
    )

    args = SendArgs.from_nodes(parse_ruby("foo()").node.children.drop(2))

    pairs = args.zip(params)

    assert_nil pairs
  end

  def test_zip4
    params = Params.new(
      required: [],
      optional: [],
      rest: Types::Name.new_instance(name: :Object),
      required_keywords: {},
      optional_keywords: {},
      rest_keywords: nil
    )

    args = SendArgs.from_nodes(parse_ruby("foo()").node.children.drop(2))

    pairs = args.zip(params)

    assert_empty pairs
  end

  def test_zip5
    params = Params.new(
      required: [],
      optional: [],
      rest: Types::Name.new_instance(name: :Object),
      required_keywords: {},
      optional_keywords: {},
      rest_keywords: nil
    )

    args = SendArgs.from_nodes(parse_ruby("foo(1)").node.children.drop(2))

    pairs = args.zip(params)

    refute_nil pairs
    assert_equal [[parse_ruby("1").node, Types::Name.new_instance(name: :Object)]], pairs
  end

  def test_zip6
    params = Params.new(
      required: [],
      optional: [],
      rest: Types::Name.new_instance(name: :Object),
      required_keywords: {},
      optional_keywords: {},
      rest_keywords: nil
    )

    args = SendArgs.from_nodes(parse_ruby("foo(1, 2)").node.children.drop(2))

    pairs = args.zip(params)

    refute_nil pairs
    assert_equal [[parse_ruby("1").node, Types::Name.new_instance(name: :Object)],
                  [parse_ruby("2").node, Types::Name.new_instance(name: :Object)]], pairs
  end

  def test_zip7
    params = Params.new(
      required: [],
      optional: [],
      rest: Types::Name.new_instance(name: :Object),
      required_keywords: {},
      optional_keywords: {},
      rest_keywords: nil
    )

    args = SendArgs.from_nodes(parse_ruby("foo(1, *args)").node.children.drop(2))

    pairs = args.zip(params)

    refute_nil pairs
    assert_equal(
      [[parse_ruby("1").node, Types::Name.new_instance(name: :Object)],
       [parse_ruby("args").node, Types::Name.new_instance(name: :"::Array",
                                                          args: [Types::Name.new_instance(name: :Object)])]],
      pairs
    )
  end

  def test_zip8
    params = Params.new(
      required: [Types::Name.new_instance(name: :String)],
      optional: [Types::Name.new_instance(name: :Integer)],
      rest: Types::Name.new_instance(name: :Object),
      required_keywords: {},
      optional_keywords: {},
      rest_keywords: nil
    )

    args = SendArgs.from_nodes(parse_ruby("foo(1, *args)").node.children.drop(2))

    pairs = args.zip(params)

    refute_nil pairs
    assert_equal(
      [[parse_ruby("1").node, Types::Name.new_instance(name: :String)],
       [parse_ruby("args").node, Types::Name.new_instance(
         name: :"::Array",
         args: [Types::Union.build(types: [Types::Name.new_instance(name: :Integer),
                                           Types::Name.new_instance(name: :Object)])]
       )]],
      pairs
    )
  end

  def test_zip9
    params = Params.new(
      required: [],
      optional: [],
      rest: nil,
      required_keywords: { foo: Types::Name.new_instance(name: :String) },
      optional_keywords: { bar: Types::Name.new_instance(name: :Integer) },
      rest_keywords: Types::Name.new_instance(name: :Object)
    )

    args = SendArgs.from_nodes(parse_ruby("foo(foo: 1, bar: 2, baz: 3, **hash)").node.children.drop(2))

    pairs = args.zip(params)

    refute_nil pairs
    assert_equal(
      [
        [parse_ruby("1").node, Types::Name.new_instance(name: :String)],
        [parse_ruby("2").node, Types::Name.new_instance(name: :Integer)],
        [parse_ruby("3").node, Types::Name.new_instance(name: :Object)],
        [parse_ruby("hash").node, Types::Name.new_instance(
          name: :Hash,
          args: [
            Types::Name.new_instance(name: :Symbol),
            Types::Name.new_instance(name: :Object)
          ]
        )]
      ],
      pairs
    )
  end

  def test_zip10
    params = Params.new(
      required: [],
      optional: [],
      rest: nil,
      required_keywords: { foo: Types::Name.new_instance(name: :String) },
      optional_keywords: { bar: Types::Name.new_instance(name: :Integer) },
      rest_keywords: Types::Name.new_instance(name: :Object)
    )

    args = SendArgs.from_nodes(parse_ruby("foo(foo: 1, **hash)").node.children.drop(2))

    pairs = args.zip(params)

    refute_nil pairs
    assert_equal(
      [
        [parse_ruby("1").node, Types::Name.new_instance(name: :String)],
        [parse_ruby("hash").node, Types::Name.new_instance(
          name: :Hash,
          args: [
            Types::Name.new_instance(name: :Symbol),
            Types::Union.new(types: [
              Types::Name.new_instance(name: :Integer),
              Types::Name.new_instance(name: :Object)
            ])
          ]
        )]
      ],
      pairs
    )
  end

  def test_zip11
    params = Params.new(
      required: [],
      optional: [],
      rest: Types::Name.new_instance(name: :String),
      required_keywords: {},
      optional_keywords: {},
      rest_keywords: nil
    )

    args = SendArgs.from_nodes(parse_ruby("foo(*[1])").node.children.drop(2))

    pairs = args.zip(params)

    refute_nil pairs
    assert_equal(
      [
        [
          parse_ruby("[1]").node,
          Types::Name.new_instance(name: :"::Array", args: [Types::Name.new_instance(name: :String)])
        ]
      ],
      pairs
    )
  end

  def test_zip12
    params = Params.new(
      required: [Types::Name.new_instance(name: :String)],
      optional: [Types::Name.new_instance(name: :Integer)],
      rest: Types::Name.new_instance(name: :String),
      required_keywords: {},
      optional_keywords: {},
      rest_keywords: nil
    )

    args = SendArgs.from_nodes(parse_ruby("foo(*(_ = nil))").node.children.drop(2))

    pairs = args.zip(params)

    refute_nil pairs
    assert_equal(
      [
        [
          parse_ruby("(_ = nil)").node,
          Types::Name.new_instance(
            name: :"::Array",
            args: [
              Types::Union.build(types: [
                Types::Name.new_instance(name: :String),
                Types::Name.new_instance(name: :Integer),
              ])
            ]
          )
        ]
      ],
      pairs
    )
  end
end
