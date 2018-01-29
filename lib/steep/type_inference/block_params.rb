module Steep
  module TypeInference
    class BlockParams
      attr_reader :params
      attr_reader :rest

      def initialize(params:, rest:)
        @params = params
        @rest = rest
      end

      def self.from_node(node)
        params = []
        rest = nil

        node.children.each do |arg|
          case arg.type
          when :arg
            params << [arg.children.first, nil]
          when :procarg0
            params << [arg.children.first, nil]
          when :optarg
            params << arg.children
          when :restarg
            rest = arg.children.first
          end
        end

        new(
          params: params,
          rest: rest
        )
      end

      def zip(params_type)
        [].tap do |zip|
          types = params_type.flat_unnamed_params
          params.each do |(var, node)|
            type = types.shift&.last || params_type.rest || AST::Types::Any.new

            if type
              zip << [var, node, type]
            end
          end

          if rest
            if types.empty?
              array = AST::Types::Name.new_instance(
                name: :Array,
                args: [params_type.rest || AST::Types::Any.new]
              )
              zip << [rest, nil, array]
            else
              union = AST::Types::Union.new(types: types.map(&:last) + [params_type.rest].compact)
              array = AST::Types::Name.new_instance(
                name: :Array,
                args: [union]
              )
              zip << [rest, nil, array]
            end
          end
        end
      end
    end
  end
end
