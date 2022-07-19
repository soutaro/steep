module Steep
  module TypeInference
    class LogicTypeInterpreter
      attr_reader :subtyping
      attr_reader :typing

      def initialize(subtyping:, typing:)
        @subtyping = subtyping
        @typing = typing
      end

      def factory
        subtyping.factory
      end

      def guess_type_from_method(node)
        if node.type == :send
          method = node.children[1]
          case method
          when :is_a?, :kind_of?, :instance_of?
            AST::Types::Logic::ReceiverIsArg.new
          when :nil?
            AST::Types::Logic::ReceiverIsNil.new
          when :!
            AST::Types::Logic::Not.new
          when :===
            AST::Types::Logic::ArgIsReceiver.new
          end
        end
      end

      def eval(env:, node:)
        objects = Set[]
        truthy_type, falsy_type, truthy_env, falsy_env = evaluate_node(env: env, node: node, refined_objects: objects)

        [truthy_env, falsy_env, objects, truthy_type, falsy_type]
      end

      def evaluate_node(env:, node:, refined_objects:)
        type = typing.type_of(node: node)

        if type.is_a?(AST::Types::Logic::Env)
          truthy_env = type.truthy
          falsy_env = type.falsy

          return [AST::Types::Boolean.new, AST::Types::Boolean.new, truthy_env, falsy_env]
        end

        case node.type
        when :lvar
          name = node.children[0]
          refined_objects << name
          truthy_type, falsy_type = factory.unwrap_optional(type)
          return [
            truthy_type,
            falsy_type,
            env.refine_types(local_variable_types: { name => truthy_type }),
            env.refine_types(local_variable_types: { name => falsy_type })
          ]
        when :lvasgn
          name, rhs = node.children
          truthy_type, falsy_type, truthy_env, falsy_env = evaluate_node(env: env, node: rhs, refined_objects: refined_objects)
          return [
            truthy_type,
            falsy_type,
            evaluate_assignment(node, truthy_env, truthy_type, refined_objects: refined_objects),
            evaluate_assignment(node, falsy_env, falsy_type, refined_objects: refined_objects)
          ]
        when :masgn
          lhs, rhs = node.children
          truthy_type, falsy_type, truthy_env, falsy_env = evaluate_node(env: env, node: rhs, refined_objects: refined_objects)
          return [
            truthy_type,
            falsy_type,
            evaluate_assignment(node, truthy_env, truthy_type, refined_objects: refined_objects),
            evaluate_assignment(node, falsy_env, falsy_type, refined_objects: refined_objects)
          ]
        when :begin
          last_node = node.children.last or raise
          return evaluate_node(env: env, node: last_node, refined_objects: refined_objects)
        when :send
          if type.is_a?(AST::Types::Any)
            type = guess_type_from_method(node) || type
          end

          case type
          when AST::Types::Logic::Base
            receiver, _, *arguments = node.children
            truthy_env, falsy_env = evaluate_method_call(env: env, type: type, receiver: receiver, arguments: arguments, refined_objects: refined_objects)

            if truthy_env && falsy_env
              return [AST::Builtin.true_type, AST::Builtin.false_type, truthy_env, falsy_env]
            end
          else
            if env[node]
              truthy_type, falsy_type = factory.unwrap_optional(type)

              refined_objects << node
              return [
                truthy_type,
                falsy_type,
                env.refine_types(pure_call_types: { node => truthy_type }),
                env.refine_types(pure_call_types: { node => falsy_type })
              ]
            end
          end
        end

        truthy_type, falsy_type = factory.unwrap_optional(type)
        return [truthy_type, falsy_type, env, env]
      end

      def evaluate_assignment(assignment_node, env, rhs_type, refined_objects:)
        case assignment_node.type
        when :lvasgn
          name, _ = assignment_node.children
          refined_objects << name
          env.refine_types(local_variable_types: { name => rhs_type })
        when :masgn
          lhs, _ = assignment_node.children

          masgn = MultipleAssignment.new()
          assignments = masgn.expand(lhs, rhs_type, false)
          unless assignments
            rhs_type_converted = try_convert(rhs_type, :to_ary)
            rhs_type_converted ||= try_convert(rhs_type, :to_a)
            rhs_type_converted ||= AST::Types::Tuple.new(types: [rhs_type])
            assignments = masgn.expand(lhs, rhs_type_converted, false)
          end

          assignments or raise

          assignments.each do |pair|
            node, type = pair
            env = evaluate_assignment(node, env, type, refined_objects: refined_objects)
          end

          env
        else
          env
        end
      end

      def refine_node_type(env:, node:, truthy_type:, falsy_type:, refined_objects:)
        case node.type
        when :lvar
          name = node.children[0]

          refined_objects << name
          [
            env.refine_types(local_variable_types: { name => truthy_type }),
            env.refine_types(local_variable_types: { name => falsy_type })
          ]
        when :lvasgn
          name, rhs = node.children

          truthy_env, falsy_env = refine_node_type(env: env, node: rhs, truthy_type: truthy_type, falsy_type: falsy_type, refined_objects: refined_objects)
          refined_objects << name
          [
            truthy_env.refine_types(local_variable_types: { name => truthy_type }),
            falsy_env.refine_types(local_variable_types: { name => falsy_type })
          ]
        when :send
          if env[node]
            refined_objects << node
            [
              env.refine_types(pure_call_types: { node => truthy_type }),
              env.refine_types(pure_call_types: { node => falsy_type })
            ]
          else
            [env, env]
          end
        when :begin
          last_node = node.children.last or raise
          refine_node_type(env: env, node: last_node, truthy_type: truthy_type, falsy_type: falsy_type, refined_objects: refined_objects)
        else
          [env, env]
        end
      end

      def evaluate_method_call(env:, type:, receiver:, arguments:, refined_objects:)
        case type
        when AST::Types::Logic::ReceiverIsNil
          if receiver && arguments.size.zero?
            receiver_type = typing.type_of(node: receiver)
            truthy_receiver, falsy_receiver = factory.unwrap_optional(receiver_type)
            refine_node_type(env: env, node: receiver, truthy_type: falsy_receiver, falsy_type: truthy_receiver, refined_objects: refined_objects)
          end
        when AST::Types::Logic::ReceiverIsArg
          if receiver && (arg = arguments[0])
            receiver_type = typing.type_of(node: receiver)
            arg_type = factory.deep_expand_alias(typing.type_of(node: arg))

            if arg_type.is_a?(AST::Types::Name::Singleton)
              truthy_type, falsy_type = type_case_select(receiver_type, arg_type.name)
              refine_node_type(env: env, node: receiver, truthy_type: truthy_type, falsy_type: falsy_type, refined_objects: refined_objects)
            end
          end
        when AST::Types::Logic::ArgIsReceiver
          if receiver && (arg = arguments[0])
            receiver_type = factory.deep_expand_alias(typing.type_of(node: receiver))
            arg_type = typing.type_of(node: arg)

            if receiver_type.is_a?(AST::Types::Name::Singleton)
              truthy_type, falsy_type = type_case_select(arg_type, receiver_type.name)
              refine_node_type(env: env, node: arg, truthy_type: truthy_type, falsy_type: falsy_type, refined_objects: refined_objects)
            end
          end
        when AST::Types::Logic::ArgEqualsReceiver
          if receiver && (arg = arguments[0])
            arg_type = factory.expand_alias(typing.type_of(node: arg))
            if (truthy_types, falsy_types = literal_var_type_case_select(receiver, arg_type))
              refine_node_type(
                env: env,
                node: arg,
                truthy_type: AST::Types::Union.build(types: truthy_types),
                falsy_type: AST::Types::Union.build(types: falsy_types),
                refined_objects: refined_objects
              )
            end
          end
        when AST::Types::Logic::Not
          if receiver
            truthy_type, falsy_type, truthy_env, falsy_env = evaluate_node(env: env, node: receiver, refined_objects: refined_objects)
            [falsy_env, truthy_env]
          end
        end
      end

      def decompose_value(node)
        case node.type
        when :lvar
          [node, Set[node.children[0]]]
        when :masgn
          _, rhs = node.children
          decompose_value(rhs)
        when :lvasgn
          var, rhs = node.children
          val, vars = decompose_value(rhs)
          [val, vars + [var]]
        when :begin
          decompose_value(node.children.last)
        when :and
          left, right = node.children
          _, left_vars = decompose_value(left)
          val, right_vars = decompose_value(right)
          [val, left_vars + right_vars]
        else
          [node, Set[]]
        end
      end

      def literal_var_type_case_select(value_node, arg_type)
        case arg_type
        when AST::Types::Union
          # @type var truthy_types: Array[AST::Types::t]
          truthy_types = []
          # @type var falsy_types: Array[AST::Types::t]
          falsy_types = []

          arg_type.types.each do |type|
            if (ts, fs = literal_var_type_case_select(value_node, type))
              truthy_types.push(*ts)
              falsy_types.push(*fs)
            else
              return
            end
          end

          [truthy_types, falsy_types]
        else
          types = [arg_type]

          case value_node.type
          when :nil
            types.partition do |type|
              type.is_a?(AST::Types::Nil) || AST::Builtin::NilClass.instance_type?(type)
            end
          when :true
            types.partition do |type|
              AST::Builtin::TrueClass.instance_type?(type) ||
                (type.is_a?(AST::Types::Literal) && type.value == true)
            end
          when :false
            types.partition do |type|
              AST::Builtin::FalseClass.instance_type?(type) ||
                (type.is_a?(AST::Types::Literal) && type.value == false)
            end
          when :int, :str, :sym
            # @type var pairs: [Array[AST::Types::t], Array[AST::Types::t]]
            pairs = [[], []]

            types.each_with_object(pairs) do |type, pair|
              true_types, false_types = pair

              case
              when type.is_a?(AST::Types::Literal)
                if type.value == value_node.children[0]
                  true_types << type
                else
                  false_types << type
                end
              else
                true_types << AST::Types::Literal.new(value: value_node.children[0])
                false_types << type
              end
            end
          end
        end
      end

      def type_case_select(type, klass)
        truth_types, false_types = type_case_select0(type, klass)

        [
          AST::Types::Union.build(types: truth_types),
          AST::Types::Union.build(types: false_types)
        ]
      end

      def type_case_select0(type, klass)
        instance_type = factory.instance_type(klass)

        case type
        when AST::Types::Union
          truthy_types = []
          falsy_types = []

          type.types.each do |ty|
            truths, falses = type_case_select0(ty, klass)

            if truths.empty?
              falsy_types.push(ty)
            else
              truthy_types.push(*truths)
              falsy_types.push(*falses)
            end
          end

          [truthy_types, falsy_types]

        when AST::Types::Name::Alias
          ty = factory.expand_alias(type)
          type_case_select0(ty, klass)

        when AST::Types::Any, AST::Types::Top
          [
            [instance_type],
            [type]
          ]

        when AST::Types::Name::Interface
          [
            [instance_type],
            [type]
          ]

        else
          relation = Subtyping::Relation.new(sub_type: type, super_type: instance_type)
          if subtyping.check(relation, constraints: Subtyping::Constraints.empty, self_type: AST::Types::Self.new, instance_type: AST::Types::Instance.new, class_type: AST::Types::Class.new).success?
            [
              [type],
              []
            ]
          else
            [
              [],
              [type]
            ]
          end
        end
      end

      def try_convert(type, method)
        case type
        when AST::Types::Any, AST::Types::Bot, AST::Types::Top, AST::Types::Var
          return
        end

        interface = factory.interface(type, private: false, self_type: type)
        if entry = interface.methods[method]
          method_type = entry.method_types.find do |method_type|
            method_type.type.params.optional?
          end

          method_type.type.return_type if method_type
        end
      rescue => exn
        Steep.log_error(exn, message: "Unexpected error when converting #{type.to_s} with #{method}")
        nil
      end
    end
  end
end
