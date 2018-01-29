require_relative "test_helper"

class BlockParamsTest < Minitest::Test
  include TestHelper

  BlockParams = Steep::TypeInference::BlockParams
  LabeledName = ASTUtils::Labeling::LabeledName
  Params = Steep::Interface::Params
  Types = Steep::AST::Types

  def test_1
    args = parse_ruby("proc {|x, y=1, *rest| }").node.children[1]
    params = BlockParams.from_node(args)

    assert_equal [
                   [LabeledName.new(name: :x, label: 1), nil],
                   [LabeledName.new(name: :y, label: 2), parse_ruby("1").node]
                 ], params.params
  end

  def test_zip1
    type = Params.new(
      required: [Types::Name.new_instance(name: :Integer)],
      optional: [],
      rest: nil,
      required_keywords: {},
      optional_keywords: {},
      rest_keywords: nil
    )

    params = BlockParams.from_node(parse_ruby("proc {|x, y=1, *rest| }").node.children[1])

    zip = params.zip(type)

    assert_equal [
                   [params.params[0][0], nil, Types::Name.new_instance(name: :Integer)],
                   [params.params[1][0], parse_ruby("1").node, Types::Any.new],
                   [params.rest, nil, Types::Name.new_instance(name: :Array, args: [Types::Any.new])]
                 ], zip
  end

  def test_zip2
    type = Params.new(
      required: [Types::Name.new_instance(name: :Integer)],
      optional: [],
      rest: Types::Name.new_instance(name: :String),
      required_keywords: {},
      optional_keywords: {},
      rest_keywords: nil
    )

    params = BlockParams.from_node(parse_ruby("proc {|x, y=1, *rest| }").node.children[1])

    zip = params.zip(type)

    assert_equal [
                   [params.params[0][0], nil, Types::Name.new_instance(name: :Integer)],
                   [params.params[1][0], parse_ruby("1").node, Types::Name.new_instance(name: :String)],
                   [params.rest, nil, Types::Name.new_instance(name: :Array,
                                                               args: [Types::Name.new_instance(name: :String)])]
                 ], zip
  end

  def test_zip3
    type = Params.new(
      required: [Types::Name.new_instance(name: :Integer)],
      optional: [Types::Name.new_instance(name: :Object)],
      rest: Types::Name.new_instance(name: :String),
      required_keywords: {},
      optional_keywords: {},
      rest_keywords: nil
    )

    params = BlockParams.from_node(parse_ruby("proc {|x, *rest| }").node.children[1])

    zip = params.zip(type)

    assert_equal [
                   [params.params[0][0], nil, Types::Name.new_instance(name: :Integer)],
                   [params.rest, nil, Types::Name.new_instance(
                     name: :Array,
                     args: [
                       Types::Union.new(types: [
                         Types::Name.new_instance(name: :Object),
                         Types::Name.new_instance(name: :String)])
                       ])
                   ]
                 ], zip
  end
end
