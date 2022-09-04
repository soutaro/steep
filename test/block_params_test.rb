require_relative "test_helper"

class BlockParamsTest < Minitest::Test
  include TestHelper
  include FactoryHelper
  include SubtypingHelper

  BlockParams = Steep::TypeInference::BlockParams
  Params = Steep::Interface::Function::Params
  Types = Steep::AST::Types
  Namespace = RBS::Namespace

  def block_params(src)
    source = parse_ruby(src)
    args = source.node.children[1]
    annotations = source.annotations(block: source.node, factory: factory, context: nil)
    params = BlockParams.from_node(args, annotations: annotations)
    yield params, args.children
  end

  def test_1
    with_factory do
      block_params("proc {|a, b = 1, *c, d, &e| }") do |params, args|
        assert_equal [
                       BlockParams::Param.new(var: args[0].children[0],
                                              type: nil,
                                              value: nil,
                                              node: args[0])
                     ],
                     params.leading_params
        assert_equal [
                       BlockParams::Param.new(var: args[1].children[0],
                                              type: nil,
                                              value: parse_ruby("1").node,
                                              node: args[1])
                     ],
                     params.optional_params
        assert_equal BlockParams::Param.new(var: args[2].children[0],
                                            type: nil,
                                            value: nil,
                                            node: args[2]),
                     params.rest_param
        assert_equal [
                       BlockParams::Param.new(var: args[3].children[0],
                                              type: nil,
                                              value: nil,
                                              node: args[3])
                     ],
                     params.trailing_params
        assert_equal(
          BlockParams::Param.new(var: args[4].children[0], type: nil, value: nil, node: args[4]),
          params.block_param
        )
      end
    end
  end

  def test_2
    with_factory do |factory|
      src = parse_ruby(<<-EOR)
# @type var a: Integer
a = 10

proc {|a, b=1, *c, d, &e|
  # @type var a: String
  # @type var c: Array[Symbol]
  # @type var e: ^() -> void
  foo()
}
      EOR

      block = src.node.children.last
      annots = src.annotations(block: block, factory: factory, context: nil)
      params = BlockParams.from_node(block.children[1], annotations: annots)
      args = block.children[1].children

      assert_equal [BlockParams::Param.new(var: args[0].children[0], type: parse_type("::String"), value: nil, node: args[0])], params.leading_params
      assert_equal [BlockParams::Param.new(var: args[1].children[0], type: nil, value: parse_ruby("1").node, node: args[1])], params.optional_params
      assert_equal BlockParams::Param.new(var: args[2].children[0], type: parse_type("::Array[::Symbol]"), value: nil, node: args[2]), params.rest_param
      assert_equal [BlockParams::Param.new(var: args[3].children[0], type: nil, value: nil, node: args[3])], params.trailing_params
      assert_equal(
        BlockParams::Param.new(
          var: args[4].children[0],
          type: parse_type("^() -> void"),
          value: nil,
          node: args[4]
        ),
        params.block_param
      )
    end
  end

  def test_zip1
    with_factory do
      type = Params.build(
        required: [Types::Name.new_instance(name: :Integer)],
        optional: [],
        rest: nil,
        required_keywords: {},
        optional_keywords: {},
        rest_keywords: nil
      )

      block_params("proc {|a, b=1, *c| }") do |params, args|
        zip = params.zip(type, nil)
        assert_equal [params.params[0], parse_type("Integer")], zip[0]
        assert_equal [params.params[1], parse_type("nil")], zip[1]
        assert_equal [params.params[2], parse_type("::Array[untyped]")], zip[2]
      end
    end
  end

  def test_zip2
    with_factory do
      type = Params.build(
        required: [parse_type("::Integer")],
        optional: [parse_type("::String")],
        rest: Types::Name.new_instance(name: :String),
        required_keywords: {},
        optional_keywords: {},
        rest_keywords: nil
      )

      block_params("proc {|a, b, *c| }") do |params, args|
        zip = params.zip(type, nil)

        assert_equal [params.params[0], parse_type("::Integer")], zip[0]
        assert_equal [params.params[1], parse_type("::String")], zip[1]
        assert_equal [params.params[2], parse_type("::Array[String]")], zip[2]
      end
    end
  end

  def test_zip3
    with_factory do
      type = Params.build(
        required: [parse_type("::Integer")],
        optional: [parse_type("::Object")],
        rest: parse_type("::String"),
        required_keywords: {},
        optional_keywords: {},
        rest_keywords: nil
      )

      block_params("proc {|x, *y| }") do |params|
        zip = params.zip(type, nil)

        assert_equal [params.params[0], parse_type("::Integer")], zip[0]
        assert_equal [params.params[1], parse_type("::Array[::Object | ::String]")], zip[1]
      end
    end
  end

  def test_zip4
    with_factory do
      type = Params.build(
        required: [parse_type("::Integer")],
        optional: [parse_type("::Object")],
        rest: parse_type("::String"),
        required_keywords: {},
        optional_keywords: {},
        rest_keywords: nil
      )

      block_params("proc {|x| }") do |params|
        zip = params.zip(type, nil)

        assert_equal 1, zip.size
        assert_equal [params.params[0], parse_type("::Integer")], zip[0]
      end
    end
  end

  def test_zip_missing_required_params
    with_factory do
      type = Params.build(
        required: [parse_type("::Integer"), parse_type("::Object")],
        optional: [],
        rest: nil,
        required_keywords: {},
        optional_keywords: {},
        rest_keywords: nil
      )

      block_params("proc { }") do |params|
        zip = params.zip(type, nil)

        assert_empty zip
      end
    end
  end

  def test_zip_with_extra_params
    with_factory do
      type = Params.build(
        required: [parse_type("::Object")],
        optional: [],
        rest: nil,
        required_keywords: {},
        optional_keywords: {},
        rest_keywords: nil
      )

      block_params("proc {|x, y| }") do |params|
        zip = params.zip(type, nil)

        assert_equal 2, zip.size
        assert_equal [params.params[0], parse_type("::Object")], zip[0]
        assert_equal [params.params[1], parse_type("nil")], zip[1]
      end
    end
  end

  def test_zip_expand_array
    with_factory do
      type = Params.build(
        required: [parse_type("::Array[::Integer]")],
        optional: [],
        rest: nil,
        required_keywords: {},
        optional_keywords: {},
        rest_keywords: nil
      )

      block_params("proc {|x,y,*z| }") do |params|
        zip = params.zip(type, nil)

        assert_equal [params.params[0], parse_type("::Integer | nil")], zip[0]
        assert_equal [params.params[1], parse_type("::Integer | nil")], zip[1]
        assert_equal [params.params[2], parse_type("::Array[::Integer]")], zip[2]
      end

      block_params("proc {|x,| }") do |params|
        zip = params.zip(type, nil)

        assert_equal [params.params[0], parse_type("::Integer | nil")], zip[0]
      end
    end
  end

  def test_zip_expand_tuple
    with_factory do
      type = Params.build(
        required: [parse_type("[::Symbol, ::Integer]")],
        optional: [],
        rest: nil,
        required_keywords: {},
        optional_keywords: {},
        rest_keywords: nil
      )

      block_params("proc {|x,y,*z| }") do |params|
        zip = params.zip(type, nil)

        assert_equal [params.params[0], parse_type("::Symbol")], zip[0]
        assert_equal [params.params[1], parse_type("::Integer")], zip[1]
        assert_equal [params.params[2], parse_type("nil")], zip[2]
      end

      block_params("proc {|x,| }") do |params|
        zip = params.zip(type, nil)

        assert_equal [params.params[0], parse_type("::Symbol")], zip[0]
      end

      block_params("proc {|x, *y| }") do |params|
        zip = params.zip(type, nil)

        assert_equal [params.params[0], parse_type("::Symbol")], zip[0]
        assert_equal [params.params[1], parse_type("::Array[::Integer]")], zip[1]
      end
    end
  end

  def test_param_type
    with_factory do |factory|
      src = parse_ruby(<<-EOR)
proc {|a, b=1, *c, d|
}
      EOR

      block = src.node
      annots = src.annotations(block: block, factory: factory, context: nil)
      params = BlockParams.from_node(block.children[1], annotations: annots)

      param_type = params.params_type()
      assert_equal [parse_type("untyped")], param_type.required
      assert_equal [parse_type("untyped")], param_type.optional
      assert_equal parse_type("untyped"), param_type.rest
      assert_equal({}, param_type.required_keywords)
      assert_equal({}, param_type.optional_keywords)
      assert_nil param_type.rest_keywords
    end
  end

  def test_param_type_with_annotation
    with_factory do |factory|
      src = parse_ruby(<<-EOR)
proc {|a, b=1, *c, d|
  # @type var a: String
  # @type var c: Array[Symbol]
  foo()
}
      EOR

      block = src.node
      annots = src.annotations(block: block, factory: factory, context: nil)
      params = BlockParams.from_node(block.children[1], annotations: annots)

      param_type = params.params_type()
      assert_equal [parse_type("::String")], param_type.required
      assert_equal [parse_type("untyped")], param_type.optional
      assert_equal parse_type("::Symbol"), param_type.rest
      assert_equal({}, param_type.required_keywords)
      assert_equal({}, param_type.optional_keywords)
      assert_nil param_type.rest_keywords
    end
  end

  def test_param_type_with_hint
    with_factory do |factory|
      src = parse_ruby(<<-EOR)
proc {|a, b=1, *c|
  # @type var a: String
  # @type var b: Integer
  # @type var c: Array[Symbol]
  foo()
}
      EOR

      block = src.node
      annots = src.annotations(block: block, factory: factory, context: nil)
      params = BlockParams.from_node(block.children[1], annotations: annots)

      yield_self do
        hint = param_type(required: ["::String"], optional: ["::Integer"], rest: "::Symbol")
        param_type = params.params_type(hint: hint)
        assert_equal "(::String, ?::Integer, *::Symbol)", param_type.to_s
      end

      yield_self do
        hint = param_type(required: ["::String"], optional: ["::Integer"])
        param_type = params.params_type(hint: hint)
        assert_equal "(::String, ?::Integer)", param_type.to_s
      end

      yield_self do
        hint = param_type(required: ["::String"])
        param_type = params.params_type(hint: hint)
        assert_equal "(::String)", param_type.to_s
      end

      yield_self do
        hint = param_type(required: ["::String"], optional: ["::Integer", "::Integer"])
        param_type = params.params_type(hint: hint)
        assert_equal "(::String, ?::Integer, ?::Integer)", param_type.to_s
      end

      yield_self do
        hint = param_type(required: ["::String"], optional: ["::Integer", "::Integer"], rest: "::Symbol")
        param_type = params.params_type(hint: hint)
        assert_equal "(::String, ?::Integer, *::Symbol)", param_type.to_s
      end

      yield_self do
        hint = param_type(required: ["::String", "::Integer"])
        param_type = params.params_type(hint: hint)
        assert_equal "(::String, ::Integer)", param_type.to_s
      end

      yield_self do
        hint = param_type(required: [])
        param_type = params.params_type(hint: hint)
        assert_equal "()", param_type.to_s
      end

      yield_self do
        hint = param_type(required: [], optional: ["::Integer"])
        param_type = params.params_type(hint: hint)
        assert_equal "(::String, ?::Integer, *::Symbol)", param_type.to_s
      end
    end
  end

  def param_type(required: [], optional: [], rest: nil, required_keywords: {}, optional_keywords: {}, rest_keywords: nil)
    Steep::Interface::Function::Params.build(
      required: required.map {|s| parse_type(s) },
      optional: optional.map {|t| parse_type(t) },
      rest: rest&.yield_self {|t| parse_type(t) },
      required_keywords: required_keywords.transform_values {|t| parse_type(t) },
      optional_keywords: optional_keywords.transform_values {|t| parse_type(t) },
      rest_keywords: rest_keywords&.yield_self {|t| parse_type(t) }
    )
  end

  def test_zip_block
    with_factory do
      block_params("proc {|&proc| }") do |params|
        params.zip(
          Params.empty,
          Steep::Interface::Block.new(
            type: parse_type("^() -> void").type,
            optional: false,
            self_type: nil
          )
        ).tap do |zip|
          assert_equal 1, zip.size
          assert_equal [params.block_param, parse_type("^() -> void")], zip[0]
        end

        params.zip(
          Params.empty,
          Steep::Interface::Block.new(
            type: parse_type("^() -> void").type,
            optional: true,
            self_type: nil
          )
        ).tap do |zip|
          assert_equal 1, zip.size
          assert_equal [params.block_param, parse_type("^() -> void | nil")], zip[0]
        end

        params.zip(
          Params.empty,
          nil
        ).tap do |zip|
          assert_equal 1, zip.size
          assert_equal [params.block_param, parse_type("nil")], zip[0]
        end
      end
    end
  end

  def test_multiple_param_parse
    with_factory do
      src = <<-RUBY
-> ((x, y)) do
  # @type var y: String
end
      RUBY
      block_params(src) do |params|
        params.leading_params[0].tap do |param|
          assert_instance_of BlockParams::MultipleParam, param
          assert_equal 2, param.params.size

          param.params[0].tap do |param|
            assert_instance_of BlockParams::Param, param
            assert_equal :x, param.var
            assert_nil param.type
          end

          param.params[1].tap do |param|
            assert_instance_of BlockParams::Param, param
            assert_equal :y, param.var
            assert_equal parse_type("::String"), param.type
          end
        end
      end
    end
  end

  def test_multiple_param_zip
    with_factory do
      src = <<-RUBY
-> ((x, y)) do
  # @type var y: String
end
      RUBY
      block_params(src) do |params|
        params.zip(
          Params.build(
            required: [parse_type("[::Integer, ::String]")],
            optional: [],
            rest: nil,
            required_keywords: {},
            optional_keywords: {},
            rest_keywords: nil
          ),
          nil
        ).tap do |zip|
          assert_equal 1, zip.size
          zip[0].tap do |pair|
            assert_equal [params.params[0], parse_type("[::Integer, ::String]")], pair
          end
        end
      end
    end
  end
end
