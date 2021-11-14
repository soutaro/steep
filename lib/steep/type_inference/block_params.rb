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
          params.push(*leading_params)
          params.push(*optional_params)
          params.push rest_param if rest_param
          params.push(*trailing_params)
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

          if var.is_a?(::AST::Node)
            return
          end

          type = annotations.var_type(lvar: var)

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

      def params_type(hint: nil)
        params_type0(hint: hint) or params_type0(hint: nil)
      end

      def params_type0(hint:)
        if hint
          case
          when leading_params.size == hint.required.size
            leadings = leading_params.map.with_index do |param, index|
              param.type || hint.required[index]
            end
          when !hint.rest && hint.optional.empty? && leading_params.size > hint.required.size
            leadings = leading_params.take(hint.required.size).map.with_index do |param, index|
              param.type || hint.required[index]
            end
          when !hint.rest && hint.optional.empty? && leading_params.size < hint.required.size
            leadings = leading_params.map.with_index do |param, index|
              param.type || hint.required[index]
            end + hint.required.drop(leading_params.size)
          else
            return nil
          end

          case
          when optional_params.size == hint.optional.size
            optionals = optional_params.map.with_index do |param, index|
              param.type || hint.optional[index]
            end
          when !hint.rest && optional_params.size > hint.optional.size
            optionals = optional_params.take(hint.optional.size).map.with_index do |param, index|
              param.type || hint.optional[index]
            end
          when !hint.rest && optional_params.size < hint.optional.size
            optionals = optional_params.map.with_index do |param, index|
              param.type || hint.optional[index]
            end + hint.optional.drop(optional_params.size)
          else
            return nil
          end

          if rest_param && hint.rest
            rest = rest_param.type&.yield_self {|ty| ty.args&.first } || hint.rest
          else
            rest = hint.rest
          end
        else
          leadings = leading_params.map {|param| param.type || AST::Types::Any.new }
          optionals = optional_params.map {|param| param.type || AST::Types::Any.new }
          rest = rest_param&.yield_self {|param| param.type&.args&.[](0) || AST::Types::Any.new }
        end

        Interface::Function::Params.build(
          required: leadings,
          optional: optionals,
          rest: rest
        )
      end

      def zip(params_type)
        if trailing_params.any?
          Steep.logger.error "Block definition with trailing required parameters are not supported yet"
        end

        [].tap do |zip|
          if expandable_params?(params_type) && expandable?
            type = params_type.required[0]

            case
            when AST::Builtin::Array.instance_type?(type)
              type_arg = type.args[0]
              params.each do |param|
                unless param == rest_param
                  zip << [param, AST::Types::Union.build(types: [type_arg, AST::Builtin.nil_type])]
                else
                  zip << [param, AST::Builtin::Array.instance_type(type_arg)]
                end
              end
            when type.is_a?(AST::Types::Tuple)
              types = type.types.dup
              (leading_params + optional_params).each do |param|
                ty = types.shift
                if ty
                  zip << [param, ty]
                else
                  zip << [param, AST::Types::Nil.new]
                end
              end

              if rest_param
                if types.any?
                  union = AST::Types::Union.build(types: types)
                  zip << [rest_param, AST::Builtin::Array.instance_type(union)]
                else
                  zip << [rest_param, AST::Types::Nil.new]
                end
              end
            end
          else
            types = params_type.flat_unnamed_params

            (leading_params + optional_params).each do |param|
              type = types.shift&.last || params_type.rest

              if type
                zip << [param, type]
              else
                zip << [param, AST::Builtin.nil_type]
              end
            end

            if rest_param
              if types.empty?
                array = AST::Builtin::Array.instance_type(params_type.rest || AST::Builtin.any_type)
                zip << [rest_param, array]
              else
                union = AST::Types::Union.build(types: types.map(&:last) + [params_type.rest])
                array = AST::Builtin::Array.instance_type(union)
                zip << [rest_param, array]
              end
            end
          end
        end
      end

      def expandable_params?(params_type)
        if params_type.flat_unnamed_params.size == 1
          case (type = params_type.required.first)
          when AST::Types::Tuple
            true
          when AST::Types::Name::Base
            AST::Builtin::Array.instance_type?(type)
          end
        end
      end

      def expandable?
        case
        when leading_params.size + trailing_params.size > 1
          true
        when (leading_params.any? || trailing_params.any?) && rest_param
          true
        when params.size == 1 && params[0].node.type == :arg
          true
        end
      end

      def each(&block)
        if block_given?
          params.each(&block)
        else
          enum_for :each
        end
      end
    end
  end
end
