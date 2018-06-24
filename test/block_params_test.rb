require_relative "test_helper"

class BlockParamsTest < Minitest::Test
  include TestHelper

  BlockParams = Steep::TypeInference::BlockParams
  LabeledName = ASTUtils::Labeling::LabeledName
  Params = Steep::Interface::Params
  Types = Steep::AST::Types

  def block_params(src)
    source = parse_ruby(src)
    args = source.node.children[1]
    params = BlockParams.from_node(args, annotations: source.annotations(block: source.node))
    yield params, args.children
  end

  def test_1
    block_params("proc {|a, b = 1, *c, d| }") do |params, args|
      assert_equal [BlockParams::Param.new(var: args[0].children[0], type: nil, value: nil, node: args[0])], params.leading_params
      assert_equal [BlockParams::Param.new(var: args[1].children[0], type: nil, value: parse_ruby("1").node, node: args[1])], params.optional_params
      assert_equal BlockParams::Param.new(var: args[2].children[0], type: nil, value: nil, node: args[2]), params.rest_param
      assert_equal [BlockParams::Param.new(var: args[3].children[0], type: nil, value: nil, node: args[3])], params.trailing_params
    end
  end

  def test_2
    src = parse_ruby(<<-EOR)
# @type var a: Integer
a = 10

proc {|a, b=1, *c, d|
  # @type var a: String
  # @type var c: Array<Symbol>
  foo()
}
    EOR

    block = src.node.children.last
    annots = src.annotations(block: block)
    params = BlockParams.from_node(block.children[1], annotations: annots)
    args = block.children[1].children

    assert_equal [BlockParams::Param.new(var: args[0].children[0], type: parse_type("String"), value: nil, node: args[0])], params.leading_params
    assert_equal [BlockParams::Param.new(var: args[1].children[0], type: nil, value: parse_ruby("1").node, node: args[1])], params.optional_params
    assert_equal BlockParams::Param.new(var: args[2].children[0], type: parse_type("Array<Symbol>"), value: nil, node: args[2]), params.rest_param
    assert_equal [BlockParams::Param.new(var: args[3].children[0], type: nil, value: nil, node: args[3])], params.trailing_params
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

    block_params("proc {|a, b=1, *c| }") do |params, args|
      zip = params.zip(type)
      assert_equal [params.params[0], parse_type("Integer")], zip[0]
      assert_equal [params.params[1], parse_type("nil")], zip[1]
      assert_equal [params.params[2], parse_type("::Array<any>")], zip[2]
    end
  end

  def test_zip2
    type = Params.new(
      required: [parse_type("::Integer")],
      optional: [parse_type("::String")],
      rest: Types::Name.new_instance(name: :String),
      required_keywords: {},
      optional_keywords: {},
      rest_keywords: nil
    )

    block_params("proc {|a, b, *c| }") do |params, args|
      zip = params.zip(type)

      assert_equal [params.params[0], parse_type("::Integer")], zip[0]
      assert_equal [params.params[1], parse_type("::String")], zip[1]
      assert_equal [params.params[2], parse_type("::Array<String>")], zip[2]
    end
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

    block_params("proc {|x, *y| }") do |params|
      zip = params.zip(type)

      assert_equal [params.params[0], parse_type("Integer")], zip[0]
      assert_equal [params.params[1], parse_type("::Array<Object | String>")], zip[1]
    end
  end

  def test_zip4
    type = Params.new(
      required: [Types::Name.new_instance(name: :Integer)],
      optional: [Types::Name.new_instance(name: :Object)],
      rest: Types::Name.new_instance(name: :String),
      required_keywords: {},
      optional_keywords: {},
      rest_keywords: nil
    )

    block_params("proc {|x| }") do |params|
      zip = params.zip(type)

      assert_equal 1, zip.size
      assert_equal [params.params[0], parse_type("Integer")], zip[0]
    end
  end
end
