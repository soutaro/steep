module Steep
  module TypeInference
    class BlockParams
      class Param
        attr_reader :var
        attr_reader :type
        attr_reader :value
        attr_reader :node

        def initialize(var:, type:, value:, node:)
          @var = var
          @type = type
          @value = value
          @node = node
        end

        def ==(other)
          other.is_a?(self.class) && other.var == var && other.type == type && other.value == value && other.node == node
        end

        alias eql? ==

        def hash
          self.class.hash ^ var.hash ^ type.hash ^ value.hash ^ node.hash
        end
      end

      attr_reader :leading_params
      attr_reader :optional_params
      attr_reader :rest_param
      attr_reader :trailing_params

      def initialize(leading_params:, optional_params:, rest_param:, trailing_params:)
        @leading_params = leading_params
        @optional_params = optional_params
        @rest_param = rest_param
        @trailing_params = trailing_params
      end

      def params
        [].tap do |params|
          params.push *leading_params
          params.push *optional_params
          params.push rest_param if rest_param
          params.push *trailing_params
        end
      end

      def self.from_node(node, annotations:)
        leading_params = []
        optional_params = []
        rest_param = nil
        trailing_params = []

        default_params = leading_params

        node.children.each do |arg|
          var = arg.children.first
          type = annotations.lookup_var_type(var.name)

          case arg.type
          when :arg, :procarg0
            default_params << Param.new(var: var, type: type, value: nil, node: arg)
          when :optarg
            default_params = trailing_params
            optional_params << Param.new(var: var, type: type, value: arg.children.last, node: arg)
          when :restarg
            default_params = trailing_params
            rest_param = Param.new(var: var, type: type, value: nil, node: arg)
          end
        end

        new(
          leading_params: leading_params,
          optional_params: optional_params,
          rest_param: rest_param,
          trailing_params: trailing_params
        )
      end

      def zip(params_type)
        if trailing_params.any?
          Steep.logger.error "Block definition with trailing required parameters are not supported yet"
        end

        [].tap do |zip|
          types = params_type.flat_unnamed_params

          (leading_params + optional_params).each do |param|
            type = types.shift&.last || params_type.rest

            if type
              zip << [param, type]
            else
              zip << [param, AST::Types::Nil.new]
            end
          end

          if rest_param
            if types.empty?
              array = AST::Types::Name.new_instance(
                name: "::Array",
                args: [params_type.rest || AST::Types::Any.new]
              )
              zip << [rest_param, array]
            else
              union = AST::Types::Union.build(types: types.map(&:last) + [params_type.rest])
              array = AST::Types::Name.new_instance(
                name: "::Array",
                args: [union]
              )
              zip << [rest_param, array]
            end
          end
        end
      end

      def each(&block)
        if block_given?
          params.each &block
        else
          enum_for :each
        end
      end
    end
  end
end
