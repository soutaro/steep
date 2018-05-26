module Steep
  module TypeInference
    class SendArgs
      attr_reader :args
      attr_reader :kw_args

      def initialize(args:, kw_args:)
        @args = args
        @kw_args = kw_args
      end

      def self.from_nodes(nodes)
        args = []
        last_hash = nil

        nodes.each do |node|
          if last_hash
            args << last_hash
            last_hash = nil
          end

          case node.type
          when :hash
            last_hash = node
          else
            args << node
          end
        end

        if last_hash
          unless kw_args?(last_hash)
            args << last_hash
            last_hash = nil
          end
        end

        new(args: args, kw_args: last_hash)
      end

      def self.kw_args?(node)
        node.children.all? do |child|
          case child.type
          when :pair
            child.children[0].type == :sym
          when :kwsplat
            true
          end
        end
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

      def zip(params)
        Set.new(
          [].tap do |pairs|
            consumed_keywords = Set.new
            rest_types = []

            params.required_keywords.each do |name, type|
              if (node = each_keyword_arg.find {|pair| pair.children[0].children[0] == name })
                pairs << [node.children[1], type]
                consumed_keywords << name
              else
                if kwsplat_nodes.any?
                  rest_types << type
                else
                  return
                end
              end
            end

            params.optional_keywords.each do |name, type|
              if (node = each_keyword_arg.find {|pair| pair.children[0].children[0] == name })
                pairs << [node.children[1], type]
                consumed_keywords << name
              else
                if kwsplat_nodes.any?
                  rest_types << type
                end
              end
            end

            if params.rest_keywords
              each_keyword_arg do |pair|
                name = pair.children[0].children[0]
                node = pair.children[1]

                unless consumed_keywords.include?(name)
                  pairs << [node, params.rest_keywords]
                end
              end

              if kwsplat_nodes.any?
                pairs << [kw_args,
                          AST::Types::Name.new_instance(
                            name: "::Hash",
                            args: [
                              AST::Types::Name.new_instance(name: "::Symbol"),
                              AST::Types::Union.build(types: rest_types + [params.rest_keywords])
                            ]
                          )]
              end
            end

            if params.has_keyword?
              if !params.rest_keywords
                if kwsplat_nodes.empty?
                  if each_keyword_arg.any? {|pair| !consumed_keywords.include?(pair.children[0].children[0]) }
                    return
                  end
                end
              end
            end

            args = self.args.dup
            unless params.has_keyword?
              args << kw_args if kw_args
            end

            arg_types = {}

            params.required.each do |param|
              if args.any?
                next_arg(args) do |arg|
                  save_arg_type(arg, param, arg_types)
                end
                consume_arg(args)
              else
                return
              end
            end

            params.optional.each do |param|
              next_arg(args) do |arg|
                save_arg_type(arg, param, arg_types)
              end
              consume_arg(args)
            end

            if args.any?
              if params.rest
                args.each do |arg|
                  save_arg_type(arg, params.rest, arg_types)
                end
              else
                if args.none? {|arg| arg.type == :splat }
                  return
                end
              end
            end

            (self.args + [kw_args].compact).each do |arg|
              types = arg_types[arg.object_id]

              if types
                if arg.type == :splat
                  type = AST::Types::Name.new_instance(name: "::Array", args: [AST::Types::Union.build(types: types)])
                else
                  type = AST::Types::Union.build(types: types)
                end
                pairs << [arg, type]
              end
            end
          end
        )
      end

      def save_arg_type(arg, type, hash)
        if hash.key?(arg.object_id)
          types = hash[arg.object_id]
        else
          types = hash[arg.object_id] = []
        end

        types << type
      end

      def next_arg(args)
        if args.any?
          case args[0].type
          when :splat
            args.each do |arg|
              yield arg
            end
          else
            yield args[0]
          end
        end
      end

      def consume_arg(args)
        if args.any?
          unless args[0].type == :splat
            args.shift
          end
        end
      end
    end
  end
end
