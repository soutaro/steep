module Steep
  module TypeInference
    class SendArgs
      attr_reader :args
      attr_reader :block_pass_arg

      def initialize(args:, block_pass_arg:)
        @args = args
        @block_pass_arg = block_pass_arg
      end

      def self.from_nodes(nodes)
        nodes = nodes.dup

        args = []
        block_pass_arg = nil

        if nodes.last&.type == :block_pass
          block_pass_arg = nodes.pop
        end

        nodes.each do |node|
          args << node
        end

        new(args: args, block_pass_arg: block_pass_arg)
      end

      def drop_first
        raise "Cannot drop first from empty args" if args.empty?
        self.class.new(args: args.drop(1), block_pass_arg: block_pass_arg)
      end

      def drop_last
        raise "Cannot drop last from empty args" if args.empty?
        self.class.new(args: args.take(args.size - 1), block_pass_arg: block_pass_arg)
      end

      def each_keyword_arg
        if block_given?
          if kw_args
            kw_args.children.each do |node|
              if node.type == :pair
                yield node
              end
            end
          end
        else
          enum_for :each_keyword_arg
        end
      end

      def kwsplat_nodes
        if kw_args
          kw_args.children.select do |node|
            node.type == :kwsplat
          end
        else
          []
        end
      end

      def zips(params, block_type)
        zip0(params, block_type).map do |pairs|
          group_pairs(pairs)
        end
      end

      def group_pairs(pairs)
        types = pairs.each_with_object({}) do |pair, hash|
          case pair
          when Array
            node, type = pair
            hash[node.__id__] ||= [node]
            hash[node.__id__] << type
          else
            hash[node.__id__] = pair
          end
        end

        types.map do |_, array|
          case array
          when Array
            node, *types_ = array
            [node, AST::Types::Intersection.build(types: types_)]
          else
            array
          end
        end
      end

      def add_pair(pairs, pair)
        pairs.map do |ps|
          if block_given?
            yield ps, pair
          else
            [pair] + ps
          end
        end
      end

      def zip0(params, block_type)
        case
        when params.empty? && args.empty?
          [[]]

        when params.required.any?
          if args.any?
            first_arg = args[0]

            case first_arg.type
            when :splat
              []
            else
              rest = drop_first.zip0(params.drop_first, block_type)
              pair = [first_arg, params.required[0]]

              add_pair(rest, pair)
            end
          else
            []
          end

        when params.has_keywords? && params.required_keywords.any?
          if args.any?
            rest = drop_last.zip0(params.without_keywords, block_type)
            last_arg = args.last

            return [] if last_arg.type == :splat

            add_pair(rest, last_arg) do |ps, p|
              ps + [p]
            end
          else
            []
          end

        when params.has_keywords? && params.required_keywords.empty?
          if args.any?
            rest = drop_last.zip0(params.without_keywords, block_type)
            last_arg = args.last

            no_keyword = zip0(params.without_keywords, block_type)

            if last_arg.type == :splat
              no_keyword
            else
              add_pair(rest, last_arg) do |ps, p|
                ps + [p]
              end + no_keyword
            end
          else
            zip0(params.without_keywords, block_type)
          end

        when params.optional.any?
          if args.any?
            first_arg = args[0]

            case first_arg.type
            when :splat
              rest = zip0(params.drop_first, block_type)
              pair = [args[0], AST::Builtin::Array.instance_type(params.optional[0])]
            else
              rest = drop_first.zip0(params.drop_first, block_type)
              pair = [args[0], params.optional[0]]
            end

            add_pair(rest, pair)
          else
            zip0(params.drop_first, block_type)
          end

        when params.rest
          if args.any?
            rest = drop_first.zip0(params, block_type)
            first_arg = args[0]

            case first_arg.type
            when :splat
              pair = [first_arg, AST::Builtin::Array.instance_type(params.rest)]
            else
              pair = [first_arg, params.rest]
            end

            add_pair(rest, pair)
          else
            zip0(params.drop_first, block_type)
          end
        else
          []
        end
      end
    end
  end
end
