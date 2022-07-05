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

      def eval(env:, type:, node:)
        value_node, vars = decompose_value(node)

        truthy_env = env
        falsy_env = env

        if type.is_a?(AST::Types::Any)
          type = guess_type_from_method(node) || type
        end

        truthy_type, falsy_type = factory.unwrap_optional(type)

        if type.is_a?(AST::Types::Logic::Base)
          case type
          when AST::Types::Logic::Env
            truthy_env = type.truthy
            falsy_env = type.falsy
          when AST::Types::Logic::ReceiverIsNil
            case value_node.type
            when :send
              receiver = value_node.children[0]

              if receiver
                receiver_type = typing.type_of(node: receiver)
                _, receiver_vars = decompose_value(receiver)

                truthy_receiver, falsy_receiver = factory.unwrap_optional(receiver_type)

                truthy_env, falsy_env = update_type_env(
                  receiver_vars,
                  truthy_type: falsy_receiver,
                  truthy_env: truthy_env,
                  falsy_type: truthy_receiver,
                  falsy_env: falsy_env
                )
              end
            end
          when AST::Types::Logic::ReceiverIsArg
            case value_node.type
            when :send
              receiver, _, arg = value_node.children

              if receiver
                _, receiver_vars = decompose_value(receiver)

                receiver_type = typing.type_of(node: receiver)
                arg_type = typing.type_of(node: arg)

                if arg_type.is_a?(AST::Types::Name::Singleton)
                  truthy_type, falsy_type = type_case_select(receiver_type, arg_type.name)

                  var_names = receiver_vars.select do |name|
                    case name
                    when :_, :__any__, :__skip__
                      false
                    else
                      true
                    end
                  end

                  truthy_env, falsy_env = update_type_env(var_names, truthy_type: truthy_type, falsy_type: falsy_type, truthy_env: truthy_env, falsy_env: falsy_env)
                end
              end
            end
          when AST::Types::Logic::ArgIsReceiver
            case value_node.type
            when :send
              receiver, _, arg = value_node.children
              arg_type = typing.type_of(node: arg)

              if receiver
                _, arg_vars = decompose_value(arg)
                receiver_type = factory.deep_expand_alias(typing.type_of(node: receiver))

                if receiver_type.is_a?(AST::Types::Name::Singleton)
                  truthy_type, falsy_type = type_case_select(arg_type, receiver_type.name)

                  truthy_env, falsy_env =
                    update_type_env(
                      arg_vars,
                      truthy_type: truthy_type,
                      truthy_env: truthy_env,
                      falsy_type: falsy_type,
                      falsy_env: falsy_env
                    )
                end
              end
            end
          when AST::Types::Logic::ArgEqualsReceiver
            case value_node.type
            when :send
              receiver, _, arg = value_node.children

              if receiver
                receiver_value, _ = decompose_value(receiver)
                _, arg_vars = decompose_value(arg)
                arg_type = factory.expand_alias(typing.type_of(node: arg))

                truthy_types, falsy_types = literal_var_type_case_select(receiver_value, arg_type)

                truthy_env, falsy_env =
                  update_type_env(
                    arg_vars,
                    truthy_type: AST::Types::Union.build(types: truthy_types),
                    truthy_env: truthy_env,
                    falsy_type: AST::Types::Union.build(types: falsy_types),
                    falsy_env: falsy_env
                  )
              end
            end
          when AST::Types::Logic::Not
            case value_node.type
            when :send
              receiver, * = value_node.children
              receiver_type = typing.type_of(node: receiver)
              falsy_env, truthy_env = eval(env: env, type: receiver_type, node: receiver)
            end
          end
        else
          truthy_env, falsy_env = update_type_env(
            vars,
            truthy_type: truthy_type,
            falsy_type: falsy_type,
            truthy_env: truthy_env,
            falsy_env: falsy_env
          )
        end

        [truthy_env, falsy_env]
      end

      def update_type_env(variables, truthy_type:, falsy_type:, truthy_env:, falsy_env:)
        truthy_hash = {}
        falsy_hash = {}

        variables.each do |name|
          truthy_hash[name] = truthy_env.assignment(name, truthy_type)
          falsy_hash[name] = falsy_env.assignment(name, falsy_type)
        end

        [
          truthy_env.merge(local_variable_types: truthy_hash),
          falsy_env.merge(local_variable_types: falsy_hash)
        ]
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
          truthy_types = []
          falsy_types = []

          arg_type.types.each do |type|
            ts, fs = literal_var_type_case_select(value_node, type)
            truthy_types.push(*ts)
            falsy_types.push(*fs)
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
            types.each.with_object([[], []]) do |type, pair|
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
          else
            [[arg_type], [arg_type]]
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
    end
  end
end
