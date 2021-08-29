module Steep
  module Diagnostic
    module Ruby
      class Base
        include Helper

        attr_reader :node
        attr_reader :location

        def initialize(node:, location: node.location.expression)
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
        def print_result_to(io, level: 1)
          printer = Drivers::TracePrinter.new(io)
          printer.print result.trace, level: level
        end

        def trace_lines
          StringIO.new.tap do |io|
            print_result_to(io)
          end.string.chomp
        end

        def detail_lines
          StringIO.new.tap do |io|
            print_result_to(io)
          end.string.chomp
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
        attr_reader :method_type
        attr_reader :method_name

        def initialize(node:, method_name:, method_type:)
          super(node: node)
          @method_name = method_name
          @method_type = method_type
        end

        def header_line
          "Unexpected positional argument"
        end
      end

      class InsufficientPositionalArguments < Base
        attr_reader :node
        attr_reader :method_name
        attr_reader :method_type

        def initialize(node:, method_name:, method_type:)
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
          @method_name = method_name
          @method_type = method_type
        end

        def header_line
          "More positional arguments are required"
        end
      end

      class UnexpectedKeywordArgument < Base
        attr_reader :node
        attr_reader :method_name
        attr_reader :method_type

        def initialize(node:, method_name:, method_type:)
          loc = case node.type
                when :pair
                  node.children[0].location.expression
                when :kwsplat
                  node.location.expression
                else
                  raise
                end
          super(node: node, location: loc)
          @method_name = method_name
          @method_type = method_type
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

        def initialize(node:, method_name:, method_type:, missing_keywords:)
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

          @method_name = method_name
          @method_type = method_type
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
        attr_reader :receiver_type
        attr_reader :result

        include ResultPrinter

        def initialize(node:, receiver_type:, expected:, actual:, result:)
          super(node: node)
          @receiver_type = receiver_type
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
                  node.loc.selector
                when :block
                  node.children[0].loc.selector
                else
                  node.loc.expression
                end
          super(node: node, location: loc)
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
          super(node: node, location: node.loc.selector)
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
          "No superclass method `#{method}` defined"
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

      class UnknownConstantAssigned < Base
        attr_reader :context
        attr_reader :name

        def initialize(node:, context:, name:)
          const = node.children[0]
          loc = if const
                  const.loc.expression.join(node.loc.name)
                else
                  node.loc.name
                end
          super(node: node, location: loc)
          @context = context
          @name = name
        end

        def header_line
          "Cannot find the declaration of constant `#{name}`"
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
          super(node: node)
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

      class ElseOnExhaustiveCase < Base
        attr_reader :type

        def initialize(node:, type:)
          super(node: node)
          @type = type
        end

        def header_line
          "The branch is unreachable because the condition is exhaustive"
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
            "Syntax `#{node.type}` is not supported in Steep"
          end
        end
      end

      class UnexpectedError < Base
        attr_reader :message
        attr_reader :error

        def initialize(node:, error:)
          super(node: node)
          @error = error
        end

        def header_line
          "UnexpectedError: #{error.message}"
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

      ALL = ObjectSpace.each_object(Class).with_object([]) do |klass, array|
        if klass < Base
          array << klass
        end
      end

      def self.all_error
        @all_error ||= ALL.each.with_object({}) do |klass, hash|
          hash[klass] = LSPFormatter::ERROR
        end.freeze
      end

      def self.default
        @default ||= all_error.merge(
          {
            ImplicitBreakValueMismatch => :warning,
            FallbackAny => :information,
            ElseOnExhaustiveCase => :warning,
            UnknownConstantAssigned => :warning,
            MethodDefinitionMissing => :information
          }
        ).freeze
      end

      def self.strict
        @strict ||= all_error.merge(
          {
            NoMethod => nil,
            ImplicitBreakValueMismatch => nil,
            FallbackAny => nil,
            ElseOnExhaustiveCase => nil,
            UnknownConstantAssigned => nil,
            MethodDefinitionMissing => nil
          }
        ).freeze
      end

      def self.lenient
        @lenient ||= all_error.merge(
          {
            NoMethod => nil,
            ImplicitBreakValueMismatch => nil,
            FallbackAny => nil,
            ElseOnExhaustiveCase => nil,
            UnknownConstantAssigned => nil,
            MethodDefinitionMissing => nil,
            UnexpectedJump => nil
          }
        ).freeze
      end
    end
  end
end
