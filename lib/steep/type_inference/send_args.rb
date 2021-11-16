module Steep
  module TypeInference
    class SendArgs
      class PositionalArgs
        class NodeParamPair
          attr_reader :node
          attr_reader :param

          def initialize(node:, param:)
            @node = node
            @param = param
          end

          include Equatable

          def to_ary
            [node, param]
          end
        end

        class NodeTypePair
          attr_reader :node
          attr_reader :type

          def initialize(node:, type:)
            @node = node
            @type = type
          end

          include Equatable

          def node_type
            case node.type
            when :splat
              AST::Builtin::Array.instance_type(type)
            else
              type
            end
          end
        end

        class SplatArg
          attr_reader :node
          attr_accessor :type

          def initialize(node:)
            @node = node
            @type = nil
          end

          include Equatable
        end

        class UnexpectedArg
          attr_reader :node

          def initialize(node:)
            @node = node
          end

          include Equatable
        end

        class MissingArg
          attr_reader :params

          def initialize(params:)
            @params = params
          end

          include Equatable
        end

        attr_reader :args
        attr_reader :index
        attr_reader :positional_params
        attr_reader :uniform

        def initialize(args:, index:, positional_params:, uniform: false)
          @args = args
          @index = index
          @positional_params = positional_params
          @uniform = uniform
        end

        def node
          args[index]
        end

        def following_args
          args[index..]
        end

        def param
          positional_params&.head
        end

        def update(index: self.index, positional_params: self.positional_params, uniform: self.uniform)
          PositionalArgs.new(args: args, index: index, positional_params: positional_params, uniform: uniform)
        end

        def next()
          case
          when !node && param.is_a?(Interface::Function::Params::PositionalParams::Required)
            [
              MissingArg.new(params: positional_params),
              update(index: index, positional_params: nil)
            ]
          when !node && param.is_a?(Interface::Function::Params::PositionalParams::Optional)
            nil
          when !node && param.is_a?(Interface::Function::Params::PositionalParams::Rest)
            nil
          when !node && !param
            nil
          when node && node.type != :splat && param.is_a?(Interface::Function::Params::PositionalParams::Required)
            [
              NodeParamPair.new(node: node, param: param),
              update(index: index+1, positional_params: positional_params.tail)
            ]
          when node && node.type != :splat && param.is_a?(Interface::Function::Params::PositionalParams::Optional)
            [
              NodeParamPair.new(node: node, param: param),
              update(index: index+1, positional_params: positional_params.tail)
            ]
          when node && node.type != :splat && param.is_a?(Interface::Function::Params::PositionalParams::Rest)
            [
              NodeParamPair.new(node: node, param: param),
              update(index: index+1)
            ]
          when node && node.type != :splat && !param
            [
              UnexpectedArg.new(node: node),
              update(index: index + 1)
            ]
          when node && node.type == :splat
            [
              SplatArg.new(node: node),
              self
            ]
          end
        end

        def uniform_type
          return nil unless positional_params
          if positional_params.each.any? {|param| param.is_a?(Interface::Function::Params::PositionalParams::Rest) }
            AST::Types::Intersection.build(types: positional_params.each.map(&:type))
          end
        end

        def consume(n, node:)
          ps = []
          params = consume0(n, node: node, params: positional_params, ps: ps)
          case params
          when UnexpectedArg
            [
              params,
              update(index: index+1, positional_params: nil)
            ]
          else
            [ps, update(index: index+1, positional_params: params)]
          end
        end

        def consume0(n, node:, params:, ps:)
          case n
          when 0
            params
          else
            head = params&.head
            case head
            when nil
              UnexpectedArg.new(node: node)
            when Interface::Function::Params::PositionalParams::Required, Interface::Function::Params::PositionalParams::Optional
              ps << head
              consume0(n-1, node: node, params: params.tail, ps: ps)
            when Interface::Function::Params::PositionalParams::Rest
              ps << head
              consume0(n-1, node: node, params: params, ps: ps)
            end
          end
        end
      end

      class KeywordArgs
        class ArgTypePairs
          attr_reader :pairs

          def initialize(pairs:)
            @pairs = pairs
          end

          include Equatable

          def [](index)
            pairs[index]
          end

          def size
            pairs.size
          end
        end

        class SplatArg
          attr_reader :node
          attr_accessor :type

          def initialize(node:)
            @node = node
            @type = nil
          end

          include Equatable
        end

        class UnexpectedKeyword
          attr_reader :keyword
          attr_reader :node

          include Equatable

          def initialize(keyword:, node:)
            @keyword = keyword
            @node = node
          end

          def key_node
            if node.type == :pair
              node.children[0]
            end
          end

          def value_node
            if node.type == :pair
              node.children[1]
            end
          end
        end

        class MissingKeyword
          attr_reader :keywords

          include Equatable

          def initialize(keywords:)
            @keywords = keywords
          end
        end

        attr_reader :kwarg_nodes
        attr_reader :keyword_params
        attr_reader :index
        attr_reader :consumed_keywords

        def initialize(kwarg_nodes:, keyword_params:, index: 0, consumed_keywords: Set[])
          @kwarg_nodes = kwarg_nodes
          @keyword_params = keyword_params
          @index = index
          @consumed_keywords = consumed_keywords
        end

        def update(index: self.index, consumed_keywords: self.consumed_keywords)
          KeywordArgs.new(
            kwarg_nodes: kwarg_nodes,
            keyword_params: keyword_params,
            index: index,
            consumed_keywords: consumed_keywords
          )
        end

        def keyword_pair
          kwarg_nodes[index]
        end

        def required_keywords
          keyword_params.requireds
        end

        def optional_keywords
          keyword_params.optionals
        end

        def rest_type
          keyword_params.rest
        end

        def keyword_type(key)
          required_keywords[key] || optional_keywords[key]
        end

        def all_keys
          keys = Set.new
          keys.merge(required_keywords.each_key)
          keys.merge(optional_keywords.each_key)
          keys.sort_by(&:to_s).to_a
        end

        def all_values
          keys = Set.new
          keys.merge(required_keywords.each_value)
          keys.merge(optional_keywords.each_value)
          keys.sort_by(&:to_s).to_a
        end

        def possible_key_type
          key_types = all_keys.map {|key| AST::Types::Literal.new(value: key) }
          key_types << AST::Builtin::Symbol.instance_type if rest_type

          AST::Types::Union.build(types: key_types)
        end

        def possible_value_type
          value_types = all_values
          value_types << rest_type if rest_type

          AST::Types::Intersection.build(types: value_types)
        end

        def next()
          node = keyword_pair

          if node
            case node.type
            when :pair
              key_node, value_node = node.children

              if key_node.type == :sym
                key = key_node.children[0]

                case
                when value_type = keyword_type(key)
                  [
                    ArgTypePairs.new(
                      pairs: [
                        [key_node, AST::Types::Literal.new(value: key)],
                        [value_node, value_type]
                      ]
                    ),
                    update(
                      index: index+1,
                      consumed_keywords: consumed_keywords + [key]
                    )
                  ]
                when value_type = rest_type
                  [
                    ArgTypePairs.new(
                      pairs: [
                        [key_node, AST::Builtin::Symbol.instance_type],
                        [value_node, value_type]
                      ]
                    ),
                    update(
                      index: index+1,
                      consumed_keywords: consumed_keywords + [key]
                    )
                  ]
                else
                  [
                    UnexpectedKeyword.new(keyword: key, node: node),
                    update(index: index+1)
                  ]
                end
              else
                if !all_keys.empty? || rest_type
                  [
                    ArgTypePairs.new(
                      pairs: [
                        [key_node, possible_key_type],
                        [value_node, possible_value_type]
                      ]
                    ),
                    update(index: index+1)
                  ]
                else
                  [
                    UnexpectedKeyword.new(keyword: nil, node: node),
                    update(index: index+1)
                  ]
                end
              end
            when :kwsplat
              [
                SplatArg.new(node: node),
                self
              ]
            end
          else
            left = Set.new(required_keywords.keys) - consumed_keywords
            unless left.empty?
              [
                MissingKeyword.new(keywords: left),
                update(consumed_keywords: consumed_keywords + left)
              ]
            end
          end
        end

        def consume_keys(keys, node:)
          consumed_keys = []
          types = []

          unexpected_keyword = nil

          keys.each do |key|
            case
            when type = keyword_type(key)
              consumed_keys << key
              types << type
            when rest_type
              types << rest_type
            else
              unexpected_keyword = key
            end
          end

          [
            if unexpected_keyword
              UnexpectedKeyword.new(keyword: unexpected_keyword, node: node)
            else
              types
            end,
            update(index: index + 1, consumed_keywords: consumed_keywords + consumed_keys)
          ]
        end
      end

      class BlockPassArg
        attr_reader :node
        attr_reader :block

        def initialize(node:, block:)
          @node = node
          @block = block
        end

        include Equatable

        def no_block?
          !node && !block
        end

        def compatible?
          if node
            block ? true : false
          else
            !block || block.optional?
          end
        end

        def block_missing?
          !node && block&.required?
        end

        def unexpected_block?
          node && !block
        end

        def pair
          raise unless compatible?

          if node && block
            [
              node,
              block.type
            ]
          end
        end

        def node_type
          type = AST::Types::Proc.new(type: block.type, block: nil)

          if block.optional?
            type = AST::Types::Union.build(types: [type, AST::Builtin.nil_type])
          end

          type
        end
      end

      attr_reader :node
      attr_reader :arguments
      attr_reader :method_type
      attr_reader :method_name

      def initialize(node:, arguments:, method_name:, method_type:)
        @node = node
        @arguments = arguments
        @method_type = method_type
        @method_name = method_name
      end

      def positional_params
        method_type.type.params.positional_params
      end

      def keyword_params
        method_type.type.params.keyword_params
      end

      def kwargs_node
        unless keyword_params.empty?
          arguments.find {|node| node.type == :kwargs }
        end
      end

      def positional_arg
        args = if keyword_params.empty?
                 arguments.take_while {|node| node.type != :block_pass }
               else
                 arguments.take_while {|node| node.type != :kwargs && node.type != :block_pass }
               end
        PositionalArgs.new(args: args, index: 0, positional_params: positional_params)
      end

      def keyword_args
        KeywordArgs.new(
          kwarg_nodes: kwargs_node&.children || [],
          keyword_params: keyword_params
        )
      end

      def block_pass_arg
        node = arguments.find {|node| node.type == :block_pass }
        block = method_type.block

        BlockPassArg.new(node: node, block: block)
      end

      def each
        if block_given?
          errors = []
          positional_count = 0

          positional_arg.tap do |args|
            while (value, args = args.next())
              yield value

              case value
              when PositionalArgs::SplatArg
                type = value.type

                case type
                when nil
                  raise
                when AST::Types::Tuple
                  ts, args = args.consume(type.types.size, node: value.node)

                  case ts
                  when Array
                    ty = AST::Types::Tuple.new(types: ts.map(&:type))
                    yield PositionalArgs::NodeTypePair.new(node: value.node, type: ty)
                  when PositionalArgs::UnexpectedArg
                    errors << ts
                    yield ts
                  end
                else
                  if t = args.uniform_type
                    args.following_args.each do |node|
                      yield PositionalArgs::NodeTypePair.new(node: node, type: t)
                    end
                  else
                    args.following_args.each do |node|
                      arg = PositionalArgs::UnexpectedArg.new(node: node)
                      yield arg
                      errors << arg
                    end
                  end

                  break
                end
              when PositionalArgs::UnexpectedArg, PositionalArgs::MissingArg
                errors << value
              end
            end
          end

          keyword_args.tap do |args|
            while (a, args = args.next)
              case a
              when KeywordArgs::MissingKeyword
                errors << a
              when KeywordArgs::UnexpectedKeyword
                errors << a
              end

              yield a

              case a
              when KeywordArgs::SplatArg
                case type = a.type
                when nil
                  raise
                when AST::Types::Record
                  keys = type.elements.keys
                  ts, args = args.consume_keys(keys, node: a.node)

                  case ts
                  when KeywordArgs::UnexpectedKeyword
                    yield ts
                    errors << ts
                  when Array
                    record = AST::Types::Record.new(elements: Hash[keys.zip(ts)])
                    yield KeywordArgs::ArgTypePairs.new(pairs: [[a.node, record]])
                  end
                else
                  args = args.update(index: args.index + 1)

                  if args.rest_type
                    type = AST::Builtin::Hash.instance_type(AST::Builtin::Symbol.instance_type, args.possible_value_type)
                    yield KeywordArgs::ArgTypePairs.new(pairs: [[a.node, type]])
                  else
                    yield KeywordArgs::UnexpectedKeyword.new(keyword: nil, node: a.node)
                  end
                end
              end
            end
          end

          pass = block_pass_arg
          # if pass.node
          #   yield pass
          # end

          diagnostics = []

          missing_keywords = []
          errors.each do |error|
            case error
            when KeywordArgs::UnexpectedKeyword
              diagnostics << Diagnostic::Ruby::UnexpectedKeywordArgument.new(
                node: error.node,
                method_type: method_type,
                method_name: method_name
              )
            when KeywordArgs::MissingKeyword
              missing_keywords.push(*error.keywords)
            when PositionalArgs::UnexpectedArg
              diagnostics << Diagnostic::Ruby::UnexpectedPositionalArgument.new(
                node: error.node,
                method_type: method_type,
                method_name: method_name
              )
            when PositionalArgs::MissingArg
              diagnostics << Diagnostic::Ruby::InsufficientPositionalArguments.new(
                node: node,
                method_name: method_name,
                method_type: method_type
              )
            end
          end

          unless missing_keywords.empty?
            diagnostics << Diagnostic::Ruby::InsufficientKeywordArguments.new(
              node: node,
              method_name: method_name,
              method_type: method_type,
              missing_keywords: missing_keywords
            )
          end

          diagnostics
        else
          enum_for :each
        end
      end
    end
  end
end
