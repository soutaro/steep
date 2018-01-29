module Steep
  module TypeInference
    class SendArgs
      attr_reader :args
      attr_reader :rest
      attr_reader :kw_args
      attr_reader :rest_kw

      def initialize(args:, rest:, kw_args:, rest_kw:)
        @args = args
        @rest = rest
        @kw_args = kw_args
        @rest_kw = rest_kw
      end

      def self.from_nodes(nodes)
        args = []
        rest = nil
        kw_args = {}
        rest_kw = nil

        until nodes.empty?
          node = nodes.shift

          case node.type
          when :splat
            rest = node.children.first
          when :hash
            if nodes.empty? && ((h, r) = kw_args?(node))
              kw_args = h
              rest_kw = r
            else
              args << node
            end
          else
            args << node
          end

        end

        new(args: args, rest: rest, kw_args: kw_args, rest_kw: rest_kw)
      end

      def self.kw_args?(node)
        hash = {}
        kw_splat = nil

        children = node.children.dup

        if children.last&.type == :kwsplat
          kw_splat = children.pop.children.first
        end

        if children.all? {|pair| pair.children.first.type == :sym }
          children.each do |pair|
            key = pair.children.first.children.last
            value = pair.children.last
            hash[key] = value
          end

          [hash, kw_splat]
        else
          nil
        end
      end

      def zip(params)
        [].tap do |pairs|
          args = self.args.dup
          ps = params.flat_unnamed_params

          while !args.empty? && !ps.empty?
            arg = args.shift
            (_, type) = ps.shift

            pairs << [arg, type]
          end

          case
          when args.empty? && !ps.empty?
            unless ps.first[0] == :optional
              return
            end

            union = AST::Types::Union.new(types: ps.map(&:last) + [params.rest])
            array = AST::Types::Name.new_instance(name: :Array, args: [union])

            if rest
              pairs << [rest, array]
            end

          when !args.empty? && ps.empty?
            if params.rest
              args.each do |arg|
                pairs << [arg, params.rest]
              end

              if rest
                pairs << [rest, AST::Types::Name.new_instance(name: :Array, args: [params.rest])]
              end
            else
              return
            end
          end

          ks = params.flat_keywords.dup
          kw_args.each do |key, node|
            type = ks.delete(key) || params.rest_keywords
            if type
              pairs << [node, type]
            else
              return
            end
          end

          if ks.any? {|name, _| params.required_keywords.key?(name) }
            return
          end

          if rest_kw
            value_type = unless ks.empty?
                           AST::Types::Union.new(types: ks.values + [params.rest_keywords])
                         else
                           params.rest_keywords
                         end
            hash = AST::Types::Name.new_instance(
              name: :Hash,
              args: [
                AST::Types::Name.new_instance(name: :Symbol),
                value_type
              ]
            )

            pairs << [rest_kw, hash]
          end
        end
      end
    end
  end
end
