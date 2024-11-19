require_relative "test_helper"

class ArgsTest < Minitest::Test
  include TestHelper
  include FactoryHelper

  SendArgs = Steep::TypeInference::SendArgs
  Params = Steep::Interface::Function::Params
  Types = Steep::AST::Types
  AST = Steep::AST

  # @rbs skip
  include Minitest::Hooks

  def around
    with_factory do
      super
    end
  end

  def method_name
    MethodName("Foo#bar")
  end

  def parse_args(source)
    node = parse_ruby(source).node
    _, _, *args = node.children

    if block_given?
      yield node, args
    else
      [node, args]
    end
  end

  def test_positional_single_arg
    parse_args("foo(1)") do |node, args|
      SendArgs.new(node: node, arguments: args, type: parse_method_type("(Integer) -> void")).tap do |args|
        arg = args.positional_arg

        pair, arg = arg.next()

        assert_instance_of SendArgs::PositionalArgs::NodeParamPair, pair
        assert_instance_of SendArgs::PositionalArgs, arg

        assert_equal args.arguments[0], pair.node
        assert_equal args.positional_params.head, pair.param

        assert_nil arg.next()
      end

      SendArgs.new(node: node, arguments: args, type: parse_method_type("(?Integer) -> void")).tap do |args|
        arg = args.positional_arg

        pair, arg = arg.next()

        assert_instance_of SendArgs::PositionalArgs::NodeParamPair, pair
        assert_instance_of SendArgs::PositionalArgs, arg

        assert_equal args.arguments[0], pair.node
        assert_equal args.positional_params.head, pair.param

        assert_nil arg.next()
      end

      SendArgs.new(node: node, arguments: args, type: parse_method_type("(*Integer) -> void")).tap do |args|
        arg = args.positional_arg

        pair, arg = arg.next()

        assert_instance_of SendArgs::PositionalArgs::NodeParamPair, pair
        assert_instance_of SendArgs::PositionalArgs, arg

        assert_equal args.arguments[0], pair.node
        assert_equal args.positional_params.head, pair.param

        assert_nil arg.next()
      end

      SendArgs.new(node: node, arguments: args, type: parse_method_type("() -> void")).tap do |args|
        arg = args.positional_arg

        value, arg = arg.next()

        assert_instance_of SendArgs::PositionalArgs::UnexpectedArg, value
        assert_instance_of SendArgs::PositionalArgs, arg

        assert_nil arg.next()
      end
    end
  end

  def test_positional_no_arg
    parse_args("foo()") do |node, args|
      SendArgs.new(node: node, arguments: args, type: parse_method_type("(Integer) -> void")).tap do |args|
        arg = args.positional_arg

        value, arg = arg.next()

        assert_instance_of SendArgs::PositionalArgs::MissingArg, value
        assert_instance_of SendArgs::PositionalArgs, arg

        assert_nil arg.next
      end

      SendArgs.new(node: node, arguments: args, type: parse_method_type("(?Integer) -> void")).tap do |args|
        arg = args.positional_arg

        assert_nil arg.next()
      end

      SendArgs.new(node: node, arguments: args, type: parse_method_type("(*Integer) -> void")).tap do |args|
        arg = args.positional_arg

        assert_nil arg.next()
      end

      SendArgs.new(node: node, arguments: args, type: parse_method_type("() -> void")).tap do |args|
        arg = args.positional_arg

        assert_nil arg.next()
      end
    end
  end

  def test_positional_consume
    parse_args("foo()") do |node, args|
      SendArgs.new(node: node, arguments: args, type: parse_method_type("(Integer, ?String, *Symbol) -> void")).tap do |args|
        arg = args.positional_arg
        int, str, sym = args.positional_params.each.to_a

        arg.consume(1, node: args.arguments[0]).tap do |params, arg|
          assert_equal [int], params
          assert_equal 1, arg.index
          assert_equal str, arg.param
        end

        arg.consume(2, node: args.arguments[0]).tap do |params, arg|
          assert_equal [int, str], params
          assert_equal 1, arg.index
          assert_equal sym, arg.param
        end

        arg.consume(4, node: args.arguments[0]).tap do |params, arg|
          assert_equal [int, str, sym, sym], params
          assert_equal 1, arg.index
          assert_equal sym, arg.param
        end
      end
    end

    parse_args("foo(*x)") do |node, args|
      SendArgs.new(node: node, arguments: args, type: parse_method_type("(Integer) -> void")).tap do |args|
        arg = args.positional_arg

        arg.consume(2, node: args.arguments[0]).tap do |params, arg|
          assert_instance_of SendArgs::PositionalArgs::UnexpectedArg, params
          assert_nil arg.positional_params
        end
      end
    end
  end

  def test_positional_rest_arg
    parse_args("foo(*a)") do |node, args|
      SendArgs.new(node: node, arguments: args, type: parse_method_type("(Integer, *Symbol) -> void")).tap do |args|
        arg = args.positional_arg

        value, arg = arg.next()

        assert_instance_of SendArgs::PositionalArgs::SplatArg, value
        assert_instance_of SendArgs::PositionalArgs, arg

        assert_equal args.arguments[0], value.node
        assert_nil value.type
      end
    end
  end

  def test_keyword_single_keyword_arg
    parse_args("foo(x: a)") do |node, args|
      SendArgs.new(node: node, arguments: args, type: parse_method_type("(x: Integer) -> void")).tap do |args|
        kwargs = args.keyword_args

        pairs, kwargs = kwargs.next()

        assert_instance_of SendArgs::KeywordArgs::ArgTypePairs, pairs

        assert_equal 2, pairs.size

        pairs[0].tap do |node, type|
          assert_equal dig(args.arguments, 0, 0, 0), node
          assert_equal parse_type(":x"), type
        end

        pairs[1].tap do |node, type|
          assert_equal dig(args.arguments, 0, 0, 1), node
          assert_equal parse_type("Integer"), type
        end

        assert_nil kwargs.next()
      end

      SendArgs.new(node: node, arguments: args, type: parse_method_type("(?x: Integer) -> void")).tap do |args|
        kwargs = args.keyword_args

        pairs, kwargs = kwargs.next()

        assert_instance_of SendArgs::KeywordArgs::ArgTypePairs, pairs

        assert_equal 2, pairs.size

        pairs[0].tap do |node, type|
          assert_equal dig(args.arguments, 0, 0, 0), node
          assert_equal parse_type(":x"), type
        end

        pairs[1].tap do |node, type|
          assert_equal dig(args.arguments, 0, 0, 1), node
          assert_equal parse_type("Integer"), type
        end

        assert_nil kwargs.next()
      end

      SendArgs.new(node: node, arguments: args, type: parse_method_type("(**Integer) -> void")).tap do |args|
        kwargs = args.keyword_args

        pairs, kwargs = kwargs.next()

        assert_instance_of SendArgs::KeywordArgs::ArgTypePairs, pairs

        assert_equal 2, pairs.size

        pairs[0].tap do |node, type|
          assert_equal dig(args.arguments, 0, 0, 0), node
          assert_equal parse_type("::Symbol"), type
        end

        pairs[1].tap do |node, type|
          assert_equal dig(args.arguments, 0, 0, 1), node
          assert_equal parse_type("Integer"), type
        end

        assert_nil kwargs.next()
      end

      SendArgs.new(node: node, arguments: args, type: parse_method_type("() -> void")).tap do |args|
        kwargs = args.keyword_args

        assert_nil kwargs.next()
      end
    end
  end

  def test_keyword_single_keyword_no_arg
    parse_args("foo()") do |node, args|
      SendArgs.new(node: node, arguments: args, type: parse_method_type("(x: Integer) -> void")).tap do |args|
        kwargs = args.keyword_args

        value, kwargs = kwargs.next()

        assert_instance_of SendArgs::KeywordArgs::MissingKeyword, value

        assert_nil kwargs.next()
      end

      SendArgs.new(node: node, arguments: args, type: parse_method_type("(?x: Integer) -> void")).tap do |args|
        kwargs = args.keyword_args

        assert_nil kwargs.next()
      end

      SendArgs.new(node: node, arguments: args, type: parse_method_type("(**Integer) -> void")).tap do |args|
        kwargs = args.keyword_args

        assert_nil kwargs.next()
      end

      SendArgs.new(node: node, arguments: args, type: parse_method_type("() -> void")).tap do |args|
        kwargs = args.keyword_args

        assert_nil kwargs.next()
      end
    end
  end

  def test_keyword_single_rocket_arg
    parse_args("foo(a() => b())") do |node, args|
      SendArgs.new(node: node, arguments: args, type: parse_method_type("(x: Integer) -> void")).tap do |args|
        kwargs = args.keyword_args

        pairs, kwargs = kwargs.next()

        assert_instance_of SendArgs::KeywordArgs::ArgTypePairs, pairs
        assert_instance_of SendArgs::KeywordArgs, kwargs

        assert_equal 2, pairs.size

        pairs[0].tap do |node, type|
          assert_equal dig(args.arguments, 0, 0, 0), node
          assert_equal parse_type(":x"), type
        end

        pairs[1].tap do |node, type|
          assert_equal dig(args.arguments, 0, 0, 1), node
          assert_equal parse_type("Integer"), type
        end

        assert_empty kwargs.consumed_keywords
      end

      SendArgs.new(node: node, arguments: args, type: parse_method_type("(?x: Integer) -> void")).tap do |args|
        kwargs = args.keyword_args

        pairs, kwargs = kwargs.next()

        assert_instance_of SendArgs::KeywordArgs::ArgTypePairs, pairs
        assert_instance_of SendArgs::KeywordArgs, kwargs

        assert_equal 2, pairs.size

        pairs[0].tap do |node, type|
          assert_equal dig(args.arguments, 0, 0, 0), node
          assert_equal parse_type(":x"), type
        end

        pairs[1].tap do |node, type|
          assert_equal dig(args.arguments, 0, 0, 1), node
          assert_equal parse_type("Integer"), type
        end

        assert_empty kwargs.consumed_keywords
      end

      SendArgs.new(node: node, arguments: args, type: parse_method_type("(**Integer) -> void")).tap do |args|
        kwargs = args.keyword_args

        pairs, kwargs = kwargs.next()

        assert_instance_of SendArgs::KeywordArgs::ArgTypePairs, pairs
        assert_instance_of SendArgs::KeywordArgs, kwargs

        assert_equal 2, pairs.size

        pairs[0].tap do |node, type|
          assert_equal dig(args.arguments, 0, 0, 0), node
          assert_equal parse_type("::Symbol"), type
        end

        pairs[1].tap do |node, type|
          assert_equal dig(args.arguments, 0, 0, 1),node
          assert_equal parse_type("Integer"), type
        end

        assert_empty kwargs.consumed_keywords
      end

      SendArgs.new(node: node, arguments: args, type: parse_method_type("() -> void")).tap do |args|
        kwargs = args.keyword_args

        assert_nil kwargs.next()
      end
    end
  end

  def test_keyword_splat_arg
    parse_args("foo(**a)") do |node, args|
      SendArgs.new(node: node, arguments: args, type: parse_method_type("(x: Integer) -> void")).tap do |args|
        kwargs = args.keyword_args

        a, kwargs = kwargs.next()

        assert_instance_of SendArgs::KeywordArgs::SplatArg, a
        assert_equal args.arguments[0].children[0], a.node
        assert_nil a.type

        assert_instance_of SendArgs::KeywordArgs, kwargs
      end
    end
  end

  def test_keyword_consume_keys
    parse_args("foo(**args)") do |node, args|
      SendArgs.new(node: node, arguments: args, type: parse_method_type("(x: Integer, y: String, **Symbol) -> void")).tap do |args|
        kwargs = args.keyword_args

        kwargs.consume_keys([:x, :z], node: kwargs.keyword_pair).tap do |types, kwargs|
          assert_equal [parse_type("Integer"), parse_type("Symbol")], types
          assert_equal Set[:x], kwargs.consumed_keywords
        end
      end

      SendArgs.new(node: node, arguments: args, type: parse_method_type("(x: Integer, y: String) -> void")).tap do |args|
        kwargs = args.keyword_args

        kwargs.consume_keys([:a], node: kwargs.keyword_pair).tap do |types, kwargs|
          assert_equal(
            SendArgs::KeywordArgs::UnexpectedKeyword.new(
              keyword: :a,
              node: kwargs.kwarg_nodes[0]
            ),
            types
          )
        end
      end
    end
  end

  def test_compat_keyword_positional_arg
    parse_args("foo(bar: baz)") do |node, args|
      # Conversion from kwargs to hash for methods without keyword params still works
      SendArgs.new(node: node, arguments: args, type: parse_method_type("(untyped) -> void")).tap do |args|
        positionals = args.positional_arg

        value, positionals = positionals.next()

        assert_instance_of SendArgs::PositionalArgs::NodeParamPair, value
        assert_instance_of SendArgs::PositionalArgs, positionals

        assert_nil positionals.next()

        keywords = args.keyword_args
        assert_nil keywords.next()
      end
    end
  end

  def test_block_pass_arg
    parse_args("foo(&bar)") do |node, args|
      SendArgs.new(node: node, arguments: args, type: parse_method_type("() { () -> void } -> void")).tap do |args|
        arg = args.block_pass_arg

        assert_operator arg, :compatible?
        assert_equal(
          [
            args.arguments[0],
            parse_method_type("() { () -> void } -> void").block.type
          ],
          arg.pair
        )
      end

      SendArgs.new(node: node, arguments: args, type: parse_method_type("() ?{ () -> void } -> void")).tap do |args|
        arg = args.block_pass_arg

        assert_operator arg, :compatible?
        assert_equal(
          [
            args.arguments[0],
            parse_method_type("() { () -> void } -> void").block.type
          ],
          arg.pair
        )
      end

      SendArgs.new(node: node, arguments: args, type: parse_method_type("() -> void")).tap do |args|
        arg = args.block_pass_arg

        refute_operator arg, :compatible?
      end
    end

    parse_args("foo()") do |node, args|
      SendArgs.new(node: node, arguments: args, type: parse_method_type("() { () -> void } -> void")).tap do |args|
        arg = args.block_pass_arg

        refute_operator arg, :compatible?
      end

      SendArgs.new(node: node, arguments: args, type: parse_method_type("() ?{ () -> void } -> void")).tap do |args|
        arg = args.block_pass_arg

        assert_operator arg, :compatible?
        assert_nil arg.pair
      end

      SendArgs.new(node: node, arguments: args, type: parse_method_type("() -> void")).tap do |args|
        arg = args.block_pass_arg

        assert_operator arg, :compatible?
        assert_nil arg.pair
      end
    end
  end

  def test_each_single_args
    parse_args("foo(1, 2, 3)") do |node, args|
      SendArgs.new(node: node, arguments: args, type: parse_method_type("(Integer, ?String, *Symbol) -> void")).tap do |args|
        types = {}

        args.each() do |value|
          case value
          when SendArgs::PositionalArgs::NodeParamPair
            types[value.node] = value.param.type
          else
            raise
          end
        end

        assert_equal parse_type("Integer"), types[args.arguments[0]]
        assert_equal parse_type("String"), types[args.arguments[1]]
        assert_equal parse_type("Symbol"), types[args.arguments[2]]
      end
    end
  end

  def test_each_missing_arg
    parse_args("foo()") do |node, args|
      SendArgs.new(node: node, arguments: args, type: parse_method_type("(Integer) -> void")).tap do |args|
        args.each() do |value|
          case value
          when SendArgs::PositionalArgs::MissingArg
            # Expected
          else
            raise
          end
        end
      end
    end
  end

  def test_each_splat_tuple
    parse_args("foo(1, *[2, 3], 4)") do |node, args|
      SendArgs.new(node: node, arguments: args, type: parse_method_type("(Integer, String, *Symbol) -> void")).tap do |args|
        pairs = {}

        args.each() do |value|
          case value
          when SendArgs::PositionalArgs::SplatArg
            value.type = parse_type("[Integer, Integer]")
          when SendArgs::PositionalArgs::NodeParamPair
            pairs[value.node] = value.param.type
          when SendArgs::PositionalArgs::NodeTypePair
            pairs[value.node] = value.type
          else
            raise
          end
        end

        assert_equal parse_type("Integer"), pairs[args.arguments[0]]
        assert_equal parse_type("[String, Symbol]"), pairs[args.arguments[1]]
        assert_equal parse_type("Symbol"), pairs[args.arguments[2]]
      end

      SendArgs.new(node: node, arguments: args, type: parse_method_type("(Integer, String) -> void")).tap do |args|
        pairs = {}

        args.each() do |value|
          case value
          when SendArgs::PositionalArgs::SplatArg
            value.type = parse_type("[Integer, Integer]")
          when SendArgs::PositionalArgs::NodeParamPair
            pairs[value.node] = value.param.type
          when SendArgs::PositionalArgs::UnexpectedArg
            pairs[value.node] = :unexpected
          else
            raise
          end
        end

        assert_equal parse_type("Integer"), pairs[args.arguments[0]]
        assert_equal :unexpected, pairs[args.arguments[1]]
        assert_equal :unexpected, pairs[args.arguments[2]]
      end
    end
  end

  def test_each_splat_array
    parse_args("foo(1, *x, 3)") do |node, args|
      SendArgs.new(node: node, arguments: args, type: parse_method_type("(Integer, String, *Symbol) -> void")).tap do |args|
        pairs = {}

        args.each() do |value|
          case value
          when SendArgs::PositionalArgs::SplatArg
            value.type = parse_type("Array[Integer]")
          when SendArgs::PositionalArgs::NodeParamPair
            pairs[value.node] = value.param.type
          when SendArgs::PositionalArgs::NodeTypePair
            pairs[value.node] = value.type
          else
            raise
          end
        end

        assert_equal parse_type("Integer"), pairs[args.arguments[0]]
        assert_equal parse_type("String & Symbol"), pairs[args.arguments[1]]
        assert_equal parse_type("String & Symbol"), pairs[args.arguments[2]]
      end

      SendArgs.new(node: node, arguments: args, type: parse_method_type("(Integer, String) -> void")).tap do |args|
        pairs = {}

        args.each() do |value|
          case value
          when SendArgs::PositionalArgs::SplatArg
            value.type = parse_type("Array[Integer]")
          when SendArgs::PositionalArgs::NodeParamPair
            pairs[value.node] = value.param.type
          when SendArgs::PositionalArgs::UnexpectedArg
            pairs[value.node] = :unexpected
          else
            raise
          end
        end

        assert_equal parse_type("Integer"), pairs[args.arguments[0]]
        assert_equal :unexpected, pairs[args.arguments[1]]
        assert_equal :unexpected, pairs[args.arguments[2]]
      end
    end
  end

  def test_each_keyword_arg
    parse_args("foo(a:1, b:2, c: 3)") do |node, args|
      SendArgs.new(node: node, arguments: args, type: parse_method_type("(a: String, ?b: Symbol, **bool) -> void")).tap do |args|
        pairs = {}

        args.each() do |value|
          case value
          when SendArgs::KeywordArgs::ArgTypePairs
            value.pairs.each do |node, type|
              pairs[node] = type
            end
          else
            raise value.inspect
          end
        end

        assert_equal parse_type(":a"), pairs[dig(args.arguments[0], 0, 0)]
        assert_equal parse_type("String"), pairs[dig(args.arguments[0], 0, 1)]
        assert_equal parse_type(":b"), pairs[dig(args.arguments[0], 1, 0)]
        assert_equal parse_type("Symbol"), pairs[dig(args.arguments[0], 1, 1)]
        assert_equal parse_type("::Symbol"), pairs[dig(args.arguments[0], 2, 0)]
        assert_equal parse_type("bool"), pairs[dig(args.arguments[0], 2, 1)]
      end
    end

    parse_args("foo(a:1, b:2)") do |node, args|
      SendArgs.new(node: node, arguments: args, type: parse_method_type("() -> void")).tap do |args|
        args.each() do |value|
          case value
          when SendArgs::PositionalArgs::UnexpectedArg
            # expected
          else
            raise
          end
        end
      end
    end
  end

  def test_each_keyword_arg_splat_record
    parse_args("foo(**x)") do |node, args|
      SendArgs.new(node: node, arguments: args, type: parse_method_type("(a: String, ?b: Symbol, **bool) -> void")).tap do |args|
        pairs = {}

        args.each() do |value|
          case value
          when SendArgs::KeywordArgs::ArgTypePairs
            value.pairs.each do |node, type|
              pairs[node] = type
            end
          when SendArgs::KeywordArgs::SplatArg
            value.type = parse_type("{ a: String }")
          end
        end

        assert_equal parse_type("{ a: String }"), pairs[dig(args.arguments[0], 0)]
      end

      SendArgs.new(node: node, arguments: args, type: parse_method_type("(a: String) -> void")).tap do |args|
        pairs = {}

        args.each() do |value|
          case value
          when SendArgs::KeywordArgs::ArgTypePairs
            value.pairs.each do |node, type|
              pairs[node] = type
            end
          when SendArgs::KeywordArgs::SplatArg
            value.type = parse_type("{ id: Integer }")
          when SendArgs::KeywordArgs::UnexpectedKeyword
            pairs[value.node] = :unexpected
          end
        end

        assert_equal :unexpected, pairs[dig(args.arguments[0], 0)]
      end
    end
  end

  def test_each_keyword_arg_splat_array
    parse_args("foo(**x)") do |node, args|
      SendArgs.new(node: node, arguments: args, type: parse_method_type("(a: String, ?b: Symbol, **bool) -> void")).tap do |args|
        pairs = {}

        errors = args.each() do |value|
          case value
          when SendArgs::KeywordArgs::ArgTypePairs
            value.pairs.each do |node, type|
              pairs[node] = type
            end
          when SendArgs::KeywordArgs::SplatArg
            value.type = parse_type("Hash[Symbol, String]")
          end
        end

        assert_equal parse_type("::Hash[::Symbol, String & Symbol & bool]"), pairs[dig(args.arguments[0], 0)]
      end

      SendArgs.new(node: node, arguments: args, type: parse_method_type("(a: String) -> void")).tap do |args|
        pairs = {}

        args.each() do |value|
          case value
          when SendArgs::KeywordArgs::ArgTypePairs
            value.pairs.each do |node, type|
              pairs[node] = type
            end
          when SendArgs::KeywordArgs::SplatArg
            value.type = parse_type("Hash[String, String]")
          when SendArgs::KeywordArgs::UnexpectedKeyword
            pairs[value.node] = :unexpected
          end
        end

        assert_equal :unexpected, pairs[dig(args.arguments[0], 0)]
      end
    end
  end

  def test_forwarded_args
    node = parse_ruby(<<~RUBY).node
      def foo(...)
        foo(1, ...)
      end
    RUBY
    node = dig(node, 2)
    _, _, *args = node.children

    [node, args].tap do |node, args|
      SendArgs.new(node: node, arguments: args, type: parse_method_type("(Integer, String) -> void")).tap do |args|
        args, _ =  args.each {}

        assert_instance_of SendArgs::ForwardedArgs, args
      end
    end
  end
end
