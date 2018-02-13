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
                   BlockParams::Param.new(var: LabeledName.new(name: :x, label: 1), type: nil, value: nil),
                   BlockParams::Param.new(var: LabeledName.new(name: :y, label: 2), type: nil, value: parse_ruby("1").node),
                 ], params.params
    assert_equal BlockParams::Param.new(var: LabeledName.new(name: :rest, label: 3), type: nil, value: nil), params.rest
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
                   [params.params[0], Types::Name.new_instance(name: :Integer)],
                   [params.params[1], Types::Any.new],
                   [params.rest, Types::Name.new_instance(name: :Array, args: [Types::Any.new])]
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
                   [params.params[0], Types::Name.new_instance(name: :Integer)],
                   [params.params[1], Types::Name.new_instance(name: :String)],
                   [params.rest, Types::Name.new_instance(name: :Array,
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
                   [params.params[0], Types::Name.new_instance(name: :Integer)],
                   [params.rest, Types::Name.new_instance(
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
