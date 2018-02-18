require_relative "test_helper"

class BlockParamsTest < Minitest::Test
  include TestHelper

  BlockParams = Steep::TypeInference::BlockParams
  LabeledName = ASTUtils::Labeling::LabeledName
  Params = Steep::Interface::Params
  Types = Steep::AST::Types

  def test_1
    src = parse_ruby("proc {|x, y=1, *rest| }")
    args = src.node.children[1]
    params = BlockParams.from_node(args, annotations: src.annotations(block: src.node))

    assert_equal [
                   BlockParams::Param.new(var: LabeledName.new(name: :x, label: 1), type: nil, value: nil, node: args.children[0]),
                   BlockParams::Param.new(var: LabeledName.new(name: :y, label: 2), type: nil, value: parse_ruby("1").node, node: args.children[1]),
                 ], params.params
    assert_equal BlockParams::Param.new(var: LabeledName.new(name: :rest, label: 3), type: nil, value: nil, node: args.children[2]), params.rest
  end

  def test_2
    src = parse_ruby(<<-EOR)
# @type var x: Integer
x = 10

proc {|x, y=1, *rest|
  # @type var x: String
  # @type var rest: Array<Symbol>
  foo()
}
    EOR

    block = src.node.children.last
    annots = src.annotations(block: block)
    params = BlockParams.from_node(block.children[1], annotations: annots)

    assert_equal [
                   BlockParams::Param.new(var: LabeledName.new(name: :x, label: 2),
                                          type: Types::Name.new_instance(name: :String),
                                          value: nil,
                                          node: block.children[1].children[0]),
                   BlockParams::Param.new(var: LabeledName.new(name: :y, label: 3),
                                          type: nil,
                                          value: parse_ruby("1").node,
                                          node: block.children[1].children[1]),
                 ], params.params
    assert_equal BlockParams::Param.new(var: LabeledName.new(name: :rest, label: 4),
                                        type: Types::Name.new_instance(name: :Array,
                                                                       args: [Types::Name.new_instance(name: :Symbol)]),
                                        value: nil,
                                        node: block.children[1].children[2]), params.rest
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

    src = parse_ruby("proc {|x, y=1, *rest| }")
    params = BlockParams.from_node(src.node.children[1],
                                   annotations: src.annotations(block: src.node))

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

    src = parse_ruby("proc {|x, y=1, *rest| }")
    params = BlockParams.from_node(src.node.children[1],
                                   annotations: src.annotations(block: src.node))

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

    src = parse_ruby("proc {|x, *rest| }")
    params = BlockParams.from_node(src.node.children[1],
                                   annotations: src.annotations(block: src.node))

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
