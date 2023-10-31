module Steep
  module Diagnostic
    module Ruby
      class Base
        include Helper

        attr_reader :node
        attr_reader :location

        def initialize(node:, location: node&.location&.expression)
          @node = node
          @location = location
        end

        def header_line
          error_name
        end

        def detail_lines
          nil
        end

        def diagnostic_code
          "Ruby::#{error_name}"
        end
      end

      module ResultPrinter
        def relation_message(relation)
          case
          when relation.type?
            relation.to_s
          when relation.method?
            if relation.super_type.is_a?(Interface::MethodType) && relation.sub_type.is_a?(Interface::MethodType)
              relation.to_s
            end
          when relation.interface?
            nil
          when relation.block?
            "(Blocks are incompatible)"
          when relation.function?
            nil
          when relation.params?
            "(Params are incompatible)"
          end
        end

        def detail_lines
          lines = StringIO.new.tap do |io|
            failure_path = result.failure_path || []
            failure_path.reverse_each.map do |result|
              relation_message(result.relation)
            end.compact.each.with_index(1) do |message, index|
              io.puts "#{"  " * (index)}#{message}"
            end
          end.string.chomp

          unless lines.empty?
            lines
          end
        end
      end

      module ResultPrinter2
        def result_line(result)
          case result
          when Subtyping::Result::Failure
            case result.error
            when Subtyping::Result::Failure::UnknownPairError
              nil
            when Subtyping::Result::Failure::UnsatisfiedConstraints
              "Unsatisfied constraints: #{result.relation}"
            when Subtyping::Result::Failure::MethodMissingError
              "Method `#{result.error.name}` is missing"
            when Subtyping::Result::Failure::BlockMismatchError
              "Incomaptible block: #{result.relation}"
            when Subtyping::Result::Failure::ParameterMismatchError
              if result.relation.params?
                "Incompatible arity: #{result.relation.super_type} and #{result.relation.sub_type}"
              else
                "Incompatible arity: #{result.relation}"
              end
            when Subtyping::Result::Failure::PolyMethodSubtyping
              "Unsupported polymorphic method comparison: #{result.relation}"
            when Subtyping::Result::Failure::SelfBindingMismatch
              "Incompatible block self type: #{result.relation}"
            end
          else
            result.relation.to_s
          end
        end

        def detail_lines
          lines = StringIO.new.tap do |io|
            failure_path = result.failure_path || []
            failure_path.reverse_each.filter_map do |result|
              result_line(result)
            end.each.with_index(1) do |message, index|
              io.puts "#{"  " * (index)}#{message}"
            end
          end.string.chomp

          unless lines.empty?
            lines
          end
        end
      end

      class IncompatibleAssignment < Base
        attr_reader :lhs_type
        attr_reader :rhs_type
        attr_reader :result

        include ResultPrinter

        def initialize(node:, lhs_type:, rhs_type:, result:)
          super(node: node)
          @lhs_type = lhs_type
          @rhs_type = rhs_type
          @result = result
        end

        def header_line
          node = node() or raise

          element = case node.type
                    when :ivasgn, :lvasgn, :gvasgn, :cvasgn
                      "a variable"
                    when :casgn
                      "a constant"
                    else
                      "an expression"
                    end
          "Cannot assign a value of type `#{rhs_type}` to #{element} of type `#{lhs_type}`"
        end
      end

      class UnexpectedPositionalArgument < Base
        attr_reader :node
        attr_reader :params

        def initialize(node:, params:)
          super(node: node)
          @params = params
        end

        def header_line
          "Unexpected positional argument"
        end
      end

      class InsufficientPositionalArguments < Base
        attr_reader :node
        attr_reader :params

        def initialize(node:, params:)
          send = case node.type
                 when :send, :csend
                   node
                 when :block, :numblock
                   node.children[0]
                 end

          loc = if send
                  send.loc.selector.with(end_pos: send.loc.expression.end_pos)
                else
                  node.loc.expression
                end

          super(node: node, location: loc)
          @params = params
        end

        def header_line
          "More positional arguments are required"
        end
      end

      class UnexpectedKeywordArgument < Base
        attr_reader :node
        attr_reader :params

        def initialize(node:, params:)
          loc = case node.type
                when :pair
                  node.children[0].location.expression
                when :kwsplat
                  node.location.expression
                else
                  raise
                end
          super(node: node, location: loc)
          @params = params
        end

        def header_line
          "Unexpected keyword argument"
        end
      end

      class InsufficientKeywordArguments < Base
        attr_reader :node
        attr_reader :method_name
        attr_reader :method_type
        attr_reader :missing_keywords

        def initialize(node:, params:, missing_keywords:)
          send = case node.type
                 when :send, :csend
                   node
                 when :block, :numblock
                   node.children[0]
                 end

          loc = if send
                  send.loc.selector.with(end_pos: send.loc.expression.end_pos)
                else
                  node.loc.expression
                end

          super(node: node, location: loc)

          @params = params
          @missing_keywords = missing_keywords
        end

        def header_line
          "More keyword arguments are required: #{missing_keywords.join(", ")}"
        end
      end

      class UnresolvedOverloading < Base
        attr_reader :node
        attr_reader :receiver_type
        attr_reader :method_name
        attr_reader :method_types

        def initialize(node:, receiver_type:, method_name:, method_types:)
          super node: node
          @receiver_type = receiver_type
          @method_name = method_name
          @method_types = method_types
        end

        def header_line
          "Cannot find compatible overloading of method `#{method_name}` of type `#{receiver_type}`"
        end

        def detail_lines
          StringIO.new.tap do |io|
            io.puts "Method types:"
            first_type, *rest_types = method_types
            defn = "  def #{method_name}"
            io.puts "#{defn}: #{first_type}"
            rest_types.each do |method_type|
              io.puts "#{" " * defn.size}| #{method_type}"
            end
          end.string.chomp
        end
      end

      class ArgumentTypeMismatch < Base
        attr_reader :node
        attr_reader :expected
        attr_reader :actual
        attr_reader :result

        include ResultPrinter

        def initialize(node:, expected:, actual:, result:)
          super(node: node)
          @expected = expected
          @actual = actual
          @result = result
        end

        def header_line
          "Cannot pass a value of type `#{actual}` as an argument of type `#{expected}`"
        end
      end

      class NoMethod < Base
        attr_reader :type
        attr_reader :method

        def initialize(node:, type:, method:)
          loc = case node.type
                when :send
                  loc = _ = nil
                  loc ||= node.loc.operator if node.loc.respond_to?(:operator)
                  loc ||= node.loc.selector if node.loc.respond_to?(:selector)
                  loc
                when :block
                  node.children[0].loc.selector
                end
          super(node: node, location: loc || node.loc.expression)
          @type = type
          @method = method
        end

        def header_line
          "Type `#{type}` does not have method `#{method}`"
        end
      end

      class ReturnTypeMismatch < Base
        attr_reader :expected
        attr_reader :actual
        attr_reader :result

        include ResultPrinter

        def initialize(node:, expected:, actual:, result:)
          super(node: node)
          @expected = expected
          @actual = actual
          @result = result
        end

        def header_line
          "The method cannot return a value of type `#{actual}` because declared as type `#{expected}`"
        end
      end

      class SetterReturnTypeMismatch < Base
        attr_reader :expected, :actual, :result, :method_name

        include ResultPrinter

        def initialize(node:, method_name:, expected:, actual:, result:)
          super(node: node)
          @method_name = method_name
          @expected = expected
          @actual = actual
          @result = result
        end

        def header_line
          "The setter method `#{method_name}` cannot return a value of type `#{actual}` because declared as type `#{expected}`"
        end
      end

      class UnexpectedBlockGiven < Base
        attr_reader :method_type

        def initialize(node:, method_type:)
          loc = node.loc.begin.join(node.loc.end)
          super(node: node, location: loc)
          @method_type = method_type
        end

        def header_line
          "The method cannot be called with a block"
        end
      end

      class RequiredBlockMissing < Base
        attr_reader :method_type

        def initialize(node:, method_type:)
          super(node: node, location: (node.type == :super || node.type == :zsuper) ? node.loc.keyword : node.loc.selector)
          @method_type = method_type
        end

        def header_line
          "The method cannot be called without a block"
        end
      end

      class BlockTypeMismatch < Base
        attr_reader :expected
        attr_reader :actual
        attr_reader :result

        include ResultPrinter

        def initialize(node:, expected:, actual:, result:)
          super(node: node)
          @expected = expected
          @actual = actual
          @result = result
        end

        def header_line
          "Cannot pass a value of type `#{actual}` as a block-pass-argument of type `#{expected}`"
        end
      end

      class BlockBodyTypeMismatch < Base
        attr_reader :expected
        attr_reader :actual
        attr_reader :result

        include ResultPrinter

        def initialize(node:, expected:, actual:, result:)
          super(node: node, location: node.loc.begin.join(node.loc.end))
          @expected = expected
          @actual = actual
          @result = result
        end

        def header_line
          "Cannot allow block body have type `#{actual}` because declared as type `#{expected}`"
        end
      end

      class BreakTypeMismatch < Base
        attr_reader :expected
        attr_reader :actual
        attr_reader :result

        include ResultPrinter

        def initialize(node:, expected:, actual:, result:)
          super(node: node)
          @expected = expected
          @actual = actual
          @result = result
        end

        def header_line
          "Cannot break with a value of type `#{actual}` because type `#{expected}` is assumed"
        end
      end

      class ImplicitBreakValueMismatch < Base
        attr_reader :jump_type
        attr_reader :result

        include ResultPrinter

        def initialize(node:, jump_type:, result:)
          super(node: node)
          @jump_type = jump_type
          @result = result
        end

        def header_line
          "Breaking without a value may result an error because a value of type `#{jump_type}` is expected"
        end
      end

      class UnexpectedJump < Base
        def header_line
          "Cannot jump from here"
        end
      end

      class UnexpectedJumpValue < Base
        def header_line
          node = node() or raise
          "The value given to #{node.type} will be ignored"
        end
      end

      class MethodArityMismatch < Base
        attr_reader :method_type

        def initialize(node:, method_type:)
          args = case node.type
                 when :def
                   node.children[1]
                 when :defs
                   node.children[2]
                 end
          super(node: node, location: args&.loc&.expression || node.loc.name)
          @method_type = method_type
        end

        def header_line
          "Method parameters are incompatible with declaration `#{method_type}`"
        end
      end

      class MethodParameterMismatch < Base
        attr_reader :method_param
        attr_reader :method_type

        def initialize(method_param:, method_type:)
          super(node: method_param.node)
          @method_param = method_param
          @method_type = method_type
        end

        def header_line
          "The method parameter is incompatible with the declaration `#{method_type}`"
        end
      end

      class DifferentMethodParameterKind < Base
        attr_reader :method_param
        attr_reader :method_type

        def initialize(method_param:, method_type:)
          super(node: method_param.node)
          @method_param = method_param
          @method_type = method_type
        end

        def header_line
          "The method parameter has different kind from the declaration `#{method_type}`"
        end
      end

      class IncompatibleMethodTypeAnnotation < Base
        attr_reader :interface_method
        attr_reader :annotation_method
        attr_reader :result

        include ResultPrinter

        def initialize(node:, interface_method:, annotation_method:, result:)
          raise
          super(node: node)
          @interface_method = interface_method
          @annotation_method = annotation_method
          @result = result
        end
      end

      class MethodReturnTypeAnnotationMismatch < Base
        attr_reader :method_type
        attr_reader :annotation_type
        attr_reader :result

        include ResultPrinter

        def initialize(node:, method_type:, annotation_type:, result:)
          super(node: node)
          @method_type = method_type
          @annotation_type = annotation_type
          @result = result
        end

        def header_line
          "Annotation `@type return` specifies type `#{annotation_type}` where declared as type `#{method_type}`"
        end
      end

      class MethodBodyTypeMismatch < Base
        attr_reader :expected
        attr_reader :actual
        attr_reader :result

        include ResultPrinter

        def initialize(node:, expected:, actual:, result:)
          super(node: node, location: node.loc.name)
          @expected = expected
          @actual = actual
          @result = result
        end

        def header_line
          "Cannot allow method body have type `#{actual}` because declared as type `#{expected}`"
        end
      end

      class SetterBodyTypeMismatch < Base
        attr_reader :expected, :actual, :result, :method_name

        include ResultPrinter

        def initialize(node:, expected:, actual:, result:, method_name:)
          super(node: node, location: node.loc.name)
          @expected = expected
          @actual = actual
          @result = result
          @method_name = method_name
        end

        def header_line
          "Setter method `#{method_name}` cannot have type `#{actual}` because declared as type `#{expected}`"
        end
      end

      class UnexpectedYield < Base
        def header_line
          "No block given for `yield`"
        end
      end

      class UnexpectedSuper < Base
        attr_reader :method

        def initialize(node:, method:)
          super(node: node)
          @method = method
        end

        def header_line
          if method
            "No superclass method `#{method}` defined"
          else
            "`super` is not allowed from outside of method"
          end
        end
      end

      class MethodDefinitionMissing < Base
        attr_reader :module_name
        attr_reader :kind
        attr_reader :missing_method

        def initialize(node:, module_name:, kind:, missing_method:)
          super(node: node, location: node.children[0].loc.expression)
          @module_name = module_name
          @kind = kind
          @missing_method = missing_method
        end

        def header_line
          method_name = case kind
                        when :module
                          ".#{missing_method}"
                        when :instance
                          "##{missing_method}"
                        end
          "Cannot find implementation of method `#{module_name}#{method_name}`"
        end
      end

      class UnexpectedDynamicMethod < Base
        attr_reader :module_name
        attr_reader :method_name

        def initialize(node:, module_name:, method_name:)
          super(node: node, location: node.children[0].loc.expression)
          @module_name = module_name
          @method_name = method_name
        end

        def header_line
          "@dynamic annotation contains unknown method name `#{method_name}`"
        end
      end

      class UnknownConstant < Base
        attr_reader :name
        attr_reader :kind

        def initialize(node:, name:)
          super(node: node, location: node.loc.name)
          @name = name
          @kind = :constant
        end

        def class!
          @kind = :class
          self
        end

        def module!
          @kind = :module
          self
        end

        def header_line
          "Cannot find the declaration of #{kind}: `#{name}`"
        end
      end

      autoload :UnknownConstantAssigned, "steep/diagnostic/deprecated/unknown_constant_assigned"
      autoload :ElseOnExhaustiveCase, "steep/diagnostic/deprecated/else_on_exhaustive_case"

      class UnknownInstanceVariable < Base
        attr_reader :name

        def initialize(node:, name:)
          super(node: node, location: node.loc.name)
          @name = name
        end

        def header_line
          "Cannot find the declaration of instance variable: `#{name}`"
        end
      end

      class UnknownGlobalVariable < Base
        attr_reader :name

        def initialize(node:, name:)
          super(node: node, location: node.loc.name)
          @name = name
        end

        def header_line
          "Cannot find the declaration of global variable: `#{name}`"
        end
      end

      class FallbackAny < Base
        def initialize(node:)
          super(node: node)
        end

        def header_line
          "Cannot detect the type of the expression"
        end
      end

      class UnsatisfiableConstraint < Base
        attr_reader :method_type
        attr_reader :var
        attr_reader :sub_type
        attr_reader :super_type
        attr_reader :result

        def initialize(node:, method_type:, var:, sub_type:, super_type:, result:)
          super(node: node)
          @method_type = method_type
          @var = var
          @sub_type = sub_type
          @super_type = super_type
          @result = result
        end

        include ResultPrinter

        def header_line
          "Unsatisfiable constraint `#{sub_type} <: #{var} <: #{super_type}` is generated through #{method_type}"
        end
      end

      class IncompatibleAnnotation < Base
        attr_reader :var_name
        attr_reader :result
        attr_reader :relation

        def initialize(node:, var_name:, result:, relation:)
          super(node: node, location: node.location.expression)
          @var_name = var_name
          @result = result
          @relation = relation
        end

        include ResultPrinter

        def header_line
          "Type annotation about `#{var_name}` is incompatible since #{relation} doesn't hold"
        end
      end

      class IncompatibleTypeCase < Base
        attr_reader :var_name
        attr_reader :result
        attr_reader :relation

        def initialize(node:, var_name:, result:, relation:)
          super(node: node)
          @var_name = var_name
          @result = result
          @relation = relation
        end

        include ResultPrinter

        def header_line
          "Type annotation for branch about `#{var_name}` is incompatible since #{relation} doesn't hold"
        end
      end

      class UnreachableBranch < Base
        def header_line
          "The branch is unreachable"
        end
      end

      class UnreachableValueBranch < Base
        attr_reader :type

        def initialize(node:, type:, location: node.location.expression)
          super(node: node, location: location)
          @type = type
        end

        def header_line
          "The branch may evaluate to a value of `#{type}` but unreachable"
        end
      end

      class UnexpectedSplat < Base
        attr_reader :type

        def initialize(node:, type:)
          super(node: node)
          @type = type
        end

        def header_line
          "Hash splat is given with object other than `Hash[X, Y]`"
        end
      end

      class ProcTypeExpected < Base
        attr_reader :type

        def initialize(node:, type:)
          super(node: node)
          @type = type
        end

        def header_line
          "Proc type is expected but `#{type.to_s}` is specified"
        end
      end

      class MultipleAssignmentConversionError < Base
        attr_reader :original_type, :returned_type

        def initialize(node:, original_type:, returned_type:)
          super(node: node)

          @node = node
          @original_type = original_type
          @returned_type = returned_type
        end

        def header_line
          "Cannot convert `#{original_type}` to Array or tuple (`#to_ary` returns `#{returned_type}`)"
        end
      end

      class UnsupportedSyntax < Base
        attr_reader :message

        def initialize(node:, message: nil)
          super(node: node)
          @message = message
        end

        def header_line
          if message
            message
          else
            node = node() or raise
            "Syntax `#{node.type}` is not supported in Steep"
          end
        end
      end

      class UnexpectedError < Base
        attr_reader :error

        def initialize(node:, error:)
          super(node: node)
          @error = error
        end

        def header_line
          "UnexpectedError: #{error.message}(#{error.class})"
        end

        def detail_lines
          if trace = error.backtrace
            io = StringIO.new

            total = trace.size
            if total > 30
              trace = trace.take(15)
            end

            trace.each.with_index do |line, index|
              io.puts "#{index+1}. #{line}"
            end

            if trace.size != total
              io.puts "  (#{total - trace.size} more backtrace)"
            end

            io.string
          end
        end
      end

      class SyntaxError < Base
        attr_reader :message

        def initialize(message: ,location:)
          super(node: nil, location: location)
          @message = message
        end

        def header_line
          "SyntaxError: #{message}"
        end
      end

      class FalseAssertion < Base
        attr_reader :node, :assertion_type, :node_type

        def initialize(node:, assertion_type:, node_type:)
          super(node: node)
          @assertion_type = assertion_type
          @node_type = node_type
        end

        def header_line
          "Assertion cannot hold: no relationship between inferred type (`#{node_type.to_s}`) and asserted type (`#{assertion_type.to_s}`)"
        end
      end

      class UnexpectedTypeArgument < Base
        attr_reader :type_arg, :method_type

        def initialize(type_arg:, method_type:)
          super(node: nil, location: type_arg.location)
          @type_arg = type_arg
          @method_type = method_type
        end

        def header_line
          "Unexpected type arg is given to method type `#{method_type.to_s}`"
        end
      end

      class InsufficientTypeArgument < Base
        attr_reader :type_args, :method_type

        def initialize(node:, type_args:, method_type:)
          super(node: node)
          @type_args = type_args
          @method_type = method_type
        end

        def header_line
          "Requires #{method_type.type_params.size} types, but #{type_args.size} given: `#{method_type.to_s}`"
        end
      end

      class TypeArgumentMismatchError < Base
        attr_reader :type_argument, :type_parameter, :result

        def initialize(type_arg:, type_param:, result:)
          super(node: nil, location: type_arg.location)
          @type_argument = type_arg
          @type_parameter = type_param
          @result = result
        end

        include ResultPrinter

        def header_line
          "Cannot pass a type `#{type_argument}` as a type parameter `#{type_parameter.to_s}`"
        end
      end

      class IncompatibleArgumentForwarding < Base
        attr_reader :method_name, :params_pair, :block_pair, :result

        def initialize(method_name:, node:, params_pair: nil, block_pair: nil, result:)
          super(node: node)
          @method_name = method_name
          @result = result
          @params_pair = params_pair
          @block_pair = block_pair
        end

        include ResultPrinter2

        def header_line
          case
          when params_pair
            "Cannot forward arguments to `#{method_name}`:"
          when block_pair
            "Cannot forward block to `#{method_name}`:"
          else
            raise
          end
        end
      end

      class ProcHintIgnored < Base
        attr_reader :hint_type, :block_node

        def initialize(hint_type:, node:)
          @hint_type = hint_type
          super(node: node)
        end

        def header_line
          "The type hint given to the block is ignored: `#{hint_type}`"
        end
      end

      class RBSError < Base
        attr_reader :error

        def initialize(error:, node:, location:)
          @error = error
          super(node: node, location: location)
        end

        def header_line
          error.header_line
        end
      end

      ALL = ObjectSpace.each_object(Class).with_object([]) do |klass, array|
        if klass < Base
          array << klass
        end
      end

      def self.all_error
        @all_error ||= ALL.each.with_object({}) do |klass, hash| #$ Hash[singleton(Base), LSPFormatter::severity]
          hash[klass] = LSPFormatter::ERROR
        end.freeze
      end

      def self.default
        @default ||= _ = all_error.merge(
          {
            ArgumentTypeMismatch => :error,
            BlockBodyTypeMismatch => :warning,
            BlockTypeMismatch => :warning,
            BreakTypeMismatch => :hint,
            DifferentMethodParameterKind => :hint,
            FallbackAny => :hint,
            FalseAssertion => :hint,
            ImplicitBreakValueMismatch => :hint,
            IncompatibleAnnotation => :hint,
            IncompatibleArgumentForwarding => :warning,
            IncompatibleAssignment => :hint,
            IncompatibleMethodTypeAnnotation => :hint,
            IncompatibleTypeCase => :hint,
            InsufficientKeywordArguments => :error,
            InsufficientPositionalArguments => :error,
            InsufficientTypeArgument => :hint,
            MethodArityMismatch => :error,
            MethodBodyTypeMismatch => :error,
            MethodDefinitionMissing => nil,
            MethodParameterMismatch => :error,
            MethodReturnTypeAnnotationMismatch => :hint,
            MultipleAssignmentConversionError => :hint,
            NoMethod => :error,
            ProcHintIgnored => :hint,
            ProcTypeExpected => :hint,
            RBSError => :information,
            RequiredBlockMissing => :error,
            ReturnTypeMismatch => :error,
            SetterBodyTypeMismatch => :information,
            SetterReturnTypeMismatch => :information,
            SyntaxError => :hint,
            TypeArgumentMismatchError => :hint,
            UnexpectedBlockGiven => :warning,
            UnexpectedDynamicMethod => :hint,
            UnexpectedError => :hint,
            UnexpectedJump => :hint,
            UnexpectedJumpValue => :hint,
            UnexpectedKeywordArgument => :error,
            UnexpectedPositionalArgument => :error,
            UnexpectedSplat => :hint,
            UnexpectedSuper => :information,
            UnexpectedTypeArgument => :hint,
            UnexpectedYield => :warning,
            UnknownConstant => :warning,
            UnknownGlobalVariable => :warning,
            UnknownInstanceVariable => :information,
            UnreachableBranch => :hint,
            UnreachableValueBranch => :hint,
            UnresolvedOverloading => :error,
            UnsatisfiableConstraint => :hint,
            UnsupportedSyntax => :hint,
          }
        ).freeze
      end

      def self.strict
        @strict ||= _ = all_error.merge(
          {
            ArgumentTypeMismatch => :error,
            BlockBodyTypeMismatch => :error,
            BlockTypeMismatch => :error,
            BreakTypeMismatch => :error,
            DifferentMethodParameterKind => :error,
            FallbackAny => :warning,
            FalseAssertion => :error,
            ImplicitBreakValueMismatch => :information,
            IncompatibleAnnotation => :error,
            IncompatibleArgumentForwarding => :error,
            IncompatibleAssignment => :error,
            IncompatibleMethodTypeAnnotation => :error,
            IncompatibleTypeCase => :error,
            InsufficientKeywordArguments => :error,
            InsufficientPositionalArguments => :error,
            InsufficientTypeArgument => :error,
            MethodArityMismatch => :error,
            MethodBodyTypeMismatch => :error,
            MethodDefinitionMissing => :hint,
            MethodParameterMismatch => :error,
            MethodReturnTypeAnnotationMismatch => :error,
            MultipleAssignmentConversionError => :error,
            NoMethod => :error,
            ProcHintIgnored => :information,
            ProcTypeExpected => :error,
            RBSError => :error,
            RequiredBlockMissing => :error,
            ReturnTypeMismatch => :error,
            SetterBodyTypeMismatch => :error,
            SetterReturnTypeMismatch => :error,
            SyntaxError => :hint,
            TypeArgumentMismatchError => :error,
            UnexpectedBlockGiven => :error,
            UnexpectedDynamicMethod => :information,
            UnexpectedError => :information,
            UnexpectedJump => :error,
            UnexpectedJumpValue => :error,
            UnexpectedKeywordArgument => :error,
            UnexpectedPositionalArgument => :error,
            UnexpectedSplat => :warning,
            UnexpectedSuper => :error,
            UnexpectedTypeArgument => :error,
            UnexpectedYield => :error,
            UnknownConstant => :error,
            UnknownGlobalVariable => :error,
            UnknownInstanceVariable => :error,
            UnreachableBranch => :information,
            UnreachableValueBranch => :warning,
            UnresolvedOverloading => :error,
            UnsatisfiableConstraint => :error,
            UnsupportedSyntax => :information,
          }
        ).freeze
      end

      def self.lenient
        @lenient ||= _ = all_error.merge(
          {
            ArgumentTypeMismatch => :information,
            BlockBodyTypeMismatch => :information,
            BlockTypeMismatch => :information,
            BreakTypeMismatch => :hint,
            DifferentMethodParameterKind => nil,
            FallbackAny => nil,
            FalseAssertion => nil,
            ImplicitBreakValueMismatch => nil,
            IncompatibleAnnotation => nil,
            IncompatibleArgumentForwarding => :information,
            IncompatibleAssignment => :hint,
            IncompatibleMethodTypeAnnotation => nil,
            IncompatibleTypeCase => nil,
            InsufficientKeywordArguments => :information,
            InsufficientPositionalArguments => :information,
            InsufficientTypeArgument => nil,
            MethodArityMismatch => :information,
            MethodBodyTypeMismatch => :warning,
            MethodDefinitionMissing => nil,
            MethodParameterMismatch => :warning,
            MethodReturnTypeAnnotationMismatch => nil,
            MultipleAssignmentConversionError => nil,
            NoMethod => :information,
            ProcHintIgnored => nil,
            ProcTypeExpected => nil,
            RBSError => :information,
            RequiredBlockMissing => :hint,
            ReturnTypeMismatch => :warning,
            SetterBodyTypeMismatch => nil,
            SetterReturnTypeMismatch => nil,
            SyntaxError => :hint,
            TypeArgumentMismatchError => nil,
            UnexpectedBlockGiven => :hint,
            UnexpectedDynamicMethod => nil,
            UnexpectedError => :hint,
            UnexpectedJump => nil,
            UnexpectedJumpValue => nil,
            UnexpectedKeywordArgument => :information,
            UnexpectedPositionalArgument => :information,
            UnexpectedSplat => nil,
            UnexpectedSuper => nil,
            UnexpectedTypeArgument => nil,
            UnexpectedYield => :information,
            UnknownConstant => :hint,
            UnknownGlobalVariable => :hint,
            UnknownInstanceVariable => :hint,
            UnreachableBranch => :hint,
            UnreachableValueBranch => :hint,
            UnresolvedOverloading => :information,
            UnsatisfiableConstraint => :hint,
            UnsupportedSyntax => :hint,
          }
        ).freeze
      end

      def self.silent
        @silent ||= ALL.each.with_object({}) do |klass, hash|
          hash[klass] = nil
        end.freeze
      end
    end
  end
end
