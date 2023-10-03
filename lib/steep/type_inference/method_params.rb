module Steep
  module TypeInference
    class MethodParams
      class BaseParameter
        attr_reader :name
        attr_reader :type
        attr_reader :node

        def initialize(name:, type:, node:)
          @name = name
          @type = type
          @node = node
        end

        def optional?
          case node.type
          when :optarg, :kwoptarg
            true
          else
            false
          end
        end

        def value
          case node.type
          when :optarg, :kwoptarg
            node.children[1]
          end
        end

        def var_type
          type || AST::Builtin.any_type
        end

        def untyped?
          !type
        end

        def ==(other)
          other.class == self.class &&
            other.name == name &&
            other.type == type &&
            other.value == value &&
            other.node == node
        end

        alias eql? ==

        def hash
          self.class.hash ^ name.hash ^ type.hash ^ value.hash ^ node.hash
        end
      end

      class PositionalParameter < BaseParameter; end
      class KeywordParameter < BaseParameter; end

      class BaseRestParameter
        attr_reader :name
        attr_reader :type
        attr_reader :node

        def initialize(name:, type:, node:)
          @name = name
          @type = type
          @node = node
        end

        def ==(other)
          other.class == self.class &&
            other.name == name &&
            other.type == type &&
            other.node == node
        end

        alias eql? ==

        def hash
          self.class.hash ^ name.hash ^ type.hash ^ node.hash
        end
      end

      class PositionalRestParameter < BaseRestParameter
        def var_type
          AST::Builtin::Array.instance_type(type || AST::Builtin.any_type)
        end
      end

      class KeywordRestParameter < BaseRestParameter
        def var_type
          AST::Builtin::Hash.instance_type(AST::Builtin::Symbol.instance_type, type || AST::Builtin.any_type)
        end
      end

      class BlockParameter
        attr_reader :name
        attr_reader :type
        attr_reader :node
        attr_reader :self_type

        def initialize(name:, type:, node:, optional:, self_type:)
          @name = name
          @type = type
          @node = node
          @optional = optional
          @self_type = self_type
        end

        def optional?
          @optional ? true : false
        end

        def var_type
          if type
            proc_type = AST::Types::Proc.new(type: type, block: nil, self_type: self_type)

            if optional?
              AST::Types::Union.build(types: [proc_type, AST::Builtin.nil_type], location: proc_type.location)
            else
              proc_type
            end
          else
            AST::Builtin.nil_type
          end
        end

        def ==(other)
          other.class == self.class &&
            other.name == name &&
            other.type == type &&
            other.node == node &&
            other.optional? == optional? &&
            other.self_type == self_type
        end

        alias eql? ==

        def hash
          self.class.hash ^ name.hash ^ type.hash ^ node.hash ^ optional?.hash ^ self_type.hash
        end
      end

      attr_reader :args
      attr_reader :method_type
      attr_reader :params
      attr_reader :errors
      attr_reader :forward_arg_type

      def initialize(args:, method_type:, forward_arg_type:)
        @args = args
        @method_type = method_type
        @params = {}
        @errors = []
        @forward_arg_type = forward_arg_type
      end

      def [](name)
        params[name] or raise "Unknown variable name: #{name}"
      end

      def param?(name)
        params.key?(name)
      end

      def size
        params.size
      end

      def each_param(&block)
        if block
          params.each_value(&block)
        else
          params.each_value
        end
      end

      def each
        if block_given?
          each_param do |param|
            yield param.name, param.var_type
          end
        else
          enum_for :each
        end
      end

      def update(forward_arg_type: self.forward_arg_type)
        MethodParams.new(args: args, method_type: method_type, forward_arg_type: forward_arg_type)
      end

      def self.empty(node:)
        # @type var args_node: ::Parser::AST::Node
        args_node =
          case node.type
          when :def
            node.children[1]
          when :defs
            node.children[2]
          else
            raise
          end

        params = new(args: args_node.children, method_type: nil, forward_arg_type: nil)

        args_node.children.each do |arg|
          # @type var arg: ::Parser::AST::Node
          case arg.type
          when :arg, :optarg
            name = arg.children[0]
            params.params[name] = PositionalParameter.new(name: name, type: nil, node: arg)
          when :kwarg, :kwoptarg
            name = arg.children[0]
            params.params[name] = KeywordParameter.new(name: name, type: nil, node: arg)
          when :restarg
            name = arg.children[0]
            params.params[name] = PositionalRestParameter.new(name: name, type: nil, node: arg)
          when :kwrestarg
            name = arg.children[0]
            params.params[name] = KeywordRestParameter.new(name: name, type: nil, node: arg)
          when :blockarg
            name = arg.children[0]
            params.params[name] = BlockParameter.new(name: name, type: nil, optional: nil, node: arg, self_type: nil)
          end
        end

        params
      end

      def self.build(node:, method_type:)
        # @type var args_node: ::Parser::AST::Node
        args_node =
          case node.type
          when :def
            node.children[1]
          when :defs
            node.children[2]
          else
            raise
          end
        original = args_node.children #: Array[Parser::AST::Node]
        args = original.dup

        instance = new(args: original, method_type: method_type, forward_arg_type: nil)

        positional_params = method_type.type.params.positional_params

        loop do
          arg = args.first or break

          case arg.type
          when :arg
            name = arg.children[0]
            param = positional_params&.head

            case param
            when Interface::Function::Params::PositionalParams::Required
              instance.params[name] = PositionalParameter.new(name: name, type: param.type, node: arg)
            when Interface::Function::Params::PositionalParams::Optional
              method_param = PositionalParameter.new(name: name, type: param.type, node: arg)
              instance.params[name] = method_param
              instance.errors << Diagnostic::Ruby::MethodParameterMismatch.new(
                method_param: method_param,
                method_type: method_type
              )
            when Interface::Function::Params::PositionalParams::Rest
              method_param = PositionalParameter.new(name: name, type: param.type, node: arg)
              instance.params[name] = method_param
              instance.errors << Diagnostic::Ruby::MethodParameterMismatch.new(
                method_param: method_param,
                method_type: method_type
              )
            when nil
              method_param = PositionalParameter.new(name: name, type: nil, node: arg)
              instance.params[name] = method_param
              instance.errors << Diagnostic::Ruby::MethodParameterMismatch.new(
                method_param: method_param,
                method_type: method_type
              )
            end

            positional_params = positional_params&.tail

          when :optarg
            name = arg.children[0]
            param = positional_params&.head

            case param
            when Interface::Function::Params::PositionalParams::Required
              method_param = PositionalParameter.new(name: name, type: param.type, node: arg)
              instance.params[name] = method_param
              instance.errors << Diagnostic::Ruby::DifferentMethodParameterKind.new(
                method_param: method_param,
                method_type: method_type
              )
            when Interface::Function::Params::PositionalParams::Optional
              instance.params[name] = PositionalParameter.new(name: name, type: param.type, node: arg)
            when Interface::Function::Params::PositionalParams::Rest
              method_param = PositionalParameter.new(name: name, type: param.type, node: arg)
              instance.params[name] = method_param
              instance.errors << Diagnostic::Ruby::DifferentMethodParameterKind.new(
                method_param: method_param,
                method_type: method_type
              )
            when nil
              method_param = PositionalParameter.new(name: name, type: nil, node: arg)
              instance.params[name] = method_param
              instance.errors << Diagnostic::Ruby::DifferentMethodParameterKind.new(
                method_param: method_param,
                method_type: method_type
              )
            end

            positional_params = positional_params&.tail
          else
            break
          end

          args.shift
        end

        if (arg = args.first) && arg.type == :forward_arg
          forward_params = method_type.type.params.update(positional_params: positional_params)
          return instance.update(forward_arg_type: [forward_params, method_type.block])
        end

        if (arg = args.first) && arg.type == :restarg
          name = arg.children[0]
          rest_types = [] #: Array[AST::Types::t]
          has_error = false

          loop do
            param = positional_params&.head

            case param
            when Interface::Function::Params::PositionalParams::Required
              rest_types << param.type
              has_error = true
            when Interface::Function::Params::PositionalParams::Optional
              rest_types << param.type
              has_error = true
            when Interface::Function::Params::PositionalParams::Rest
              rest_types << param.type
              positional_params = nil
              args.shift
              break
            when nil
              has_error = true
              break
            end

            if positional_params
              positional_params = positional_params.tail
            else
              raise "Fatal error"
            end
          end

          type = rest_types.empty? ? nil : AST::Types::Union.build(types: rest_types)

          method_param = PositionalRestParameter.new(name: name, type: type, node: arg)
          instance.params[name] = method_param
          if has_error
            instance.errors << Diagnostic::Ruby::DifferentMethodParameterKind.new(
              method_param: method_param,
              method_type: method_type
            )
          end
        end

        if positional_params
          instance.errors << Diagnostic::Ruby::MethodArityMismatch.new(node: node, method_type: method_type)
        end

        keyword_params = method_type.type.params.keyword_params
        keywords = keyword_params.keywords

        loop do
          arg = args.first or break

          case arg.type
          when :kwarg
            name = arg.children[0]

            case
            when type = keyword_params.requireds[name]
              instance.params[name] = KeywordParameter.new(name: name, type: type, node: arg)
              keywords.delete(name)
            when type = keyword_params.optionals[name]
              method_param = KeywordParameter.new(name: name, type: type, node: arg)
              instance.params[name] = method_param
              instance.errors << Diagnostic::Ruby::MethodParameterMismatch.new(
                method_param: method_param,
                method_type: method_type
              )
              keywords.delete(name)
            when type = keyword_params.rest
              method_param = KeywordParameter.new(name: name, type: type, node: arg)
              instance.params[name] = method_param
              instance.errors << Diagnostic::Ruby::MethodParameterMismatch.new(
                method_param: method_param,
                method_type: method_type
              )
              keywords.delete(name)
            else
              method_param = KeywordParameter.new(name: name, type: nil, node: arg)
              instance.params[name] = method_param
              instance.errors << Diagnostic::Ruby::MethodParameterMismatch.new(
                method_param: method_param,
                method_type: method_type
              )
            end
          when :kwoptarg
            name = arg.children[0]

            case
            when type = keyword_params.requireds[name]
              method_param = KeywordParameter.new(name: name, type: type, node: arg)
              instance.params[name] = method_param
              instance.errors << Diagnostic::Ruby::DifferentMethodParameterKind.new(
                method_param: method_param,
                method_type: method_type
              )
              keywords.delete(name)
            when type = keyword_params.optionals[name]
              method_param = KeywordParameter.new(name: name, type: type, node: arg)
              instance.params[name] = method_param
              keywords.delete(name)
            when type = keyword_params.rest
              method_param = KeywordParameter.new(name: name, type: type, node: arg)
              instance.params[name] = method_param
              instance.errors << Diagnostic::Ruby::DifferentMethodParameterKind.new(
                method_param: method_param,
                method_type: method_type
              )
              keywords.delete(name)
            else
              method_param = KeywordParameter.new(name: name, type: nil, node: arg)
              instance.params[name] = method_param
              instance.errors << Diagnostic::Ruby::DifferentMethodParameterKind.new(
                method_param: method_param,
                method_type: method_type
              )
            end
          else
            break
          end

          args.shift
        end

        if (arg = args.first) && arg.type == :kwrestarg
          name = arg.children[0]
          rest_types = [] #: Array[AST::Types::t]
          has_error = false

          keywords.each do |keyword|
            rest_types << (keyword_params.requireds[keyword] || keyword_params.optionals[keyword])
            has_error = true
          end
          keywords.clear

          if keyword_params.rest
            rest_types << keyword_params.rest
          else
            has_error = true
          end

          type = rest_types.empty? ? nil : AST::Types::Union.build(types: rest_types)

          method_param = KeywordRestParameter.new(name: name, type: type, node: arg)
          instance.params[name] = method_param

          if has_error
            instance.errors << Diagnostic::Ruby::DifferentMethodParameterKind.new(
              method_param: method_param,
              method_type: method_type
            )
          end

          args.shift
        else
          if !keywords.empty? || keyword_params.rest
            instance.errors << Diagnostic::Ruby::MethodArityMismatch.new(
              node: node,
              method_type: method_type
            )
          end
        end

        if (arg = args.first) && arg.type == :blockarg
          name = arg.children[0] #: Symbol

          if method_type.block
            instance.params[name] = BlockParameter.new(
              name: name,
              type: method_type.block.type,
              optional: method_type.block.optional?,
              node: arg,
              self_type: method_type.block.self_type
            )
          else
            instance.params[name] = BlockParameter.new(
              name: name,
              type: nil,
              optional: nil,
              node: arg,
              self_type: nil
            )
          end
        end

        instance
      end
    end
  end
end
