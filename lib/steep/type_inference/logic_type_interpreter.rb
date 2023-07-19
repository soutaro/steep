module Steep
  module TypeInference
    class LogicTypeInterpreter
      class Result < Struct.new(:env, :type, :unreachable, keyword_init: true)
        def update_env
          env = yield()
          Result.new(type: type, env: env, unreachable: unreachable)
        end

        def update_type
          Result.new(type: yield, env: env, unreachable: unreachable)
        end

        def unreachable!
          self.unreachable = true
          self
        end
      end

      attr_reader :subtyping
      attr_reader :typing
      attr_reader :config

      def initialize(subtyping:, typing:, config:)
        @subtyping = subtyping
        @typing = typing
        @config = config
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

      TRUE = AST::Types::Literal.new(value: true)
      FALSE = AST::Types::Literal.new(value: false)
      BOOL = AST::Types::Boolean.new
      BOT = AST::Types::Bot.new
      UNTYPED = AST::Types::Any.new

      def eval(env:, node:)
        evaluate_node(env: env, node: node)
      end

      def evaluate_node(env:, node:, type: typing.type_of(node: node))
        if type.is_a?(AST::Types::Logic::Env)
          truthy_env = type.truthy
          falsy_env = type.falsy

          truthy_type, falsy_type = factory.partition_union(type.type)

          return [
            Result.new(env: truthy_env, type: truthy_type || TRUE, unreachable: !truthy_type),
            Result.new(env: falsy_env, type: falsy_type || FALSE, unreachable: !falsy_type)
          ]
        end

        if type.is_a?(AST::Types::Bot)
          return [
            Result.new(env: env, type: type, unreachable: true),
            Result.new(env: env, type: type, unreachable: true),
          ]
        end

        case node.type
        when :lvar
          name = node.children[0]
          truthy_type, falsy_type = factory.partition_union(type)

          truthy_result =
            if truthy_type
              Result.new(type: truthy_type, env: env.refine_types(local_variable_types: { name => truthy_type }), unreachable: false)
            else
              Result.new(type: type, env: env, unreachable: true)
            end

          falsy_result =
            if falsy_type
              Result.new(type: falsy_type, env: env.refine_types(local_variable_types: { name => falsy_type }), unreachable: false)
            else
              Result.new(type: type, env: env, unreachable: true)
            end

          return [truthy_result, falsy_result]

        when :lvasgn
          name, rhs = node.children
          if TypeConstruction::SPECIAL_LVAR_NAMES.include?(name)
            return [
              Result.new(type: type, env: env, unreachable: false),
              Result.new(type: type, env: env, unreachable: false)
            ]
          end

          truthy_result, falsy_result = evaluate_node(env: env, node: rhs)

          return [
            truthy_result.update_env { evaluate_assignment(node, truthy_result.env, truthy_result.type) },
            falsy_result.update_env { evaluate_assignment(node, falsy_result.env, falsy_result.type) }
          ]

        when :masgn
          _, rhs = node.children
          truthy_result, falsy_result = evaluate_node(env: env, node: rhs)

          return [
            truthy_result.update_env { evaluate_assignment(node, truthy_result.env, truthy_result.type) },
            falsy_result.update_env { evaluate_assignment(node, falsy_result.env, falsy_result.type) }
          ]

        when :begin
          last_node = node.children.last or raise
          return evaluate_node(env: env, node: last_node)

        when :csend
          if type.is_a?(AST::Types::Any)
            type = guess_type_from_method(node) || type
          end

          receiver, _, *arguments = node.children
          receiver_type = typing.type_of(node: receiver)

          truthy_receiver, falsy_receiver = evaluate_node(env: env, node: receiver)
          truthy_type, _ = factory.partition_union(type)

          truthy_result, falsy_result = evaluate_node(
            env: truthy_receiver.env,
            node: node.updated(:send),
            type: truthy_type || type
          )
          truthy_result.unreachable! if truthy_receiver.unreachable

          falsy_result = Result.new(
            env: env.join(falsy_receiver.env, falsy_result.env),
            unreachable: falsy_result.unreachable && falsy_receiver.unreachable,
            type: falsy_result.type
          )

          return [truthy_result, falsy_result]

        when :send
          if type.is_a?(AST::Types::Any)
            type = guess_type_from_method(node) || type
          end

          case type
          when AST::Types::Logic::Base
            receiver, _, *arguments = node.children
            if (truthy_result, falsy_result = evaluate_method_call(env: env, type: type, receiver: receiver, arguments: arguments))
              return [truthy_result, falsy_result]
            end
          else
            if env[node]
              truthy_type, falsy_type = factory.partition_union(type)

              truthy_result =
                if truthy_type
                  Result.new(type: truthy_type, env: env.refine_types(pure_call_types: { node => truthy_type }), unreachable: false)
                else
                  Result.new(type: type, env: env, unreachable: true)
                end

              falsy_result =
                if falsy_type
                  Result.new(type: falsy_type, env: env.refine_types(pure_call_types: { node => falsy_type }), unreachable: false)
                else
                  Result.new(type: type, env: env, unreachable: true)
                end

              return [truthy_result, falsy_result]
            end
          end
        end

        truthy_type, falsy_type = factory.partition_union(type)
        return [
          Result.new(type: truthy_type || BOT, env: env, unreachable: truthy_type.nil?),
          Result.new(type: falsy_type || BOT, env: env, unreachable: falsy_type.nil?)
        ]
      end

      def evaluate_assignment(assignment_node, env, rhs_type)
        case assignment_node.type
        when :lvasgn
          name, _ = assignment_node.children
          if TypeConstruction::SPECIAL_LVAR_NAMES.include?(name)
            env
          else
            env.refine_types(local_variable_types: { name => rhs_type })
          end
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

          unless assignments
            raise "Multiple assignment rhs doesn't look correct: #{rhs_type.to_s} (#{assignment_node.location.expression&.source_line})"
          end

          assignments.each do |pair|
            node, type = pair
            env = evaluate_assignment(node, env, type)
          end

          env
        else
          env
        end
      end

      def refine_node_type(env:, node:, truthy_type:, falsy_type:)
        case node.type
        when :lvar
          name = node.children[0]

          if TypeConstruction::SPECIAL_LVAR_NAMES.include?(name)
            [env, env]
          else
            [
              env.refine_types(local_variable_types: { name => truthy_type }),
              env.refine_types(local_variable_types: { name => falsy_type })
            ]
          end

        when :lvasgn
          name, rhs = node.children

          truthy_env, falsy_env = refine_node_type(env: env, node: rhs, truthy_type: truthy_type, falsy_type: falsy_type)

          if TypeConstruction::SPECIAL_LVAR_NAMES.include?(name)
            [truthy_env, falsy_env]
          else
            [
              truthy_env.refine_types(local_variable_types: { name => truthy_type }),
              falsy_env.refine_types(local_variable_types: { name => falsy_type })
            ]
          end

        when :send
          if env[node]
            [
              env.refine_types(pure_call_types: { node => truthy_type }),
              env.refine_types(pure_call_types: { node => falsy_type })
            ]
          else
            [env, env]
          end
        when :begin
          last_node = node.children.last or raise
          refine_node_type(env: env, node: last_node, truthy_type: truthy_type, falsy_type: falsy_type)
        else
          [env, env]
        end
      end

      def evaluate_method_call(env:, type:, receiver:, arguments:)
        case type
        when AST::Types::Logic::ReceiverIsNil
          if receiver && arguments.size.zero?
            receiver_type = typing.type_of(node: receiver)
            unwrap = factory.unwrap_optional(receiver_type)
            truthy_receiver = AST::Builtin.nil_type
            falsy_receiver = unwrap || receiver_type

            truthy_env, falsy_env = refine_node_type(
              env: env,
              node: receiver,
              truthy_type: truthy_receiver,
              falsy_type: falsy_receiver
            )

            truthy_result = Result.new(type: TRUE, env: truthy_env, unreachable: false)
            truthy_result.unreachable! if no_subtyping?(sub_type: AST::Builtin.nil_type, super_type: receiver_type)

            falsy_result = Result.new(type: FALSE, env: falsy_env, unreachable: false)
            falsy_result.unreachable! unless unwrap

            [truthy_result, falsy_result]
          end

        when AST::Types::Logic::ReceiverIsArg
          if receiver && (arg = arguments[0])
            receiver_type = typing.type_of(node: receiver)
            arg_type = factory.deep_expand_alias(typing.type_of(node: arg))

            if arg_type.is_a?(AST::Types::Name::Singleton)
              truthy_type, falsy_type = type_case_select(receiver_type, arg_type.name)
              truthy_env, falsy_env = refine_node_type(
                env: env,
                node: receiver,
                truthy_type: truthy_type || factory.instance_type(arg_type.name),
                falsy_type: falsy_type || UNTYPED
              )

              truthy_result = Result.new(type: TRUE, env: truthy_env, unreachable: false)
              truthy_result.unreachable! unless truthy_type

              falsy_result = Result.new(type: FALSE, env: falsy_env, unreachable: false)
              falsy_result.unreachable! unless falsy_type

              [truthy_result, falsy_result]
            end
          end

        when AST::Types::Logic::ArgIsReceiver
          if receiver && (arg = arguments[0])
            receiver_type = factory.deep_expand_alias(typing.type_of(node: receiver))
            arg_type = typing.type_of(node: arg)

            if receiver_type.is_a?(AST::Types::Name::Singleton)
              truthy_type, falsy_type = type_case_select(arg_type, receiver_type.name)
              truthy_env, falsy_env = refine_node_type(
                env: env,
                node: arg,
                truthy_type: truthy_type || factory.instance_type(receiver_type.name),
                falsy_type: falsy_type || UNTYPED
              )

              truthy_result = Result.new(type: TRUE, env: truthy_env, unreachable: false)
              truthy_result.unreachable! unless truthy_type

              falsy_result = Result.new(type: FALSE, env: falsy_env, unreachable: false)
              falsy_result.unreachable! unless falsy_type

              [truthy_result, falsy_result]
            end
          end
        when AST::Types::Logic::ArgEqualsReceiver
          if receiver && (arg = arguments[0])
            arg_type = factory.expand_alias(typing.type_of(node: arg))
            if (truthy_types, falsy_types = literal_var_type_case_select(receiver, arg_type))
              truthy_env, falsy_env = refine_node_type(
                env: env,
                node: arg,
                truthy_type: truthy_types.empty? ? BOT : AST::Types::Union.build(types: truthy_types),
                falsy_type: falsy_types.empty? ? BOT : AST::Types::Union.build(types: falsy_types)
              )

              truthy_result = Result.new(type: TRUE, env: truthy_env, unreachable: false)
              truthy_result.unreachable! if truthy_types.empty?

              falsy_result = Result.new(type: FALSE, env: falsy_env, unreachable: false)
              falsy_result.unreachable! if falsy_types.empty?

              [truthy_result, falsy_result]
            end
          end

        when AST::Types::Logic::ArgIsAncestor
          if receiver && (arg = arguments[0])
            receiver_type = typing.type_of(node: receiver)
            arg_type = factory.deep_expand_alias(typing.type_of(node: arg))

            if arg_type.is_a?(AST::Types::Name::Singleton)
              truthy_type = arg_type
              falsy_type = receiver_type
              truthy_env, falsy_env = refine_node_type(
                env: env,
                node: receiver,
                truthy_type: truthy_type,
                falsy_type: falsy_type
              )

              truthy_result = Result.new(type: TRUE, env: truthy_env, unreachable: false)
              truthy_result.unreachable! unless truthy_type

              falsy_result = Result.new(type: FALSE, env: falsy_env, unreachable: false)
              falsy_result.unreachable! unless falsy_type

              [truthy_result, falsy_result]
            end
          end

        when AST::Types::Logic::Not
          if receiver
            truthy_result, falsy_result = evaluate_node(env: env, node: receiver)
            [
              falsy_result.update_type { TRUE },
              truthy_result.update_type { FALSE }
            ]
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
        when AST::Types::Boolean
          [[arg_type], [arg_type]]
        when AST::Types::Top, AST::Types::Any
          [[arg_type], [arg_type]]
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
          truth_types.empty? ? nil : AST::Types::Union.build(types: truth_types),
          false_types.empty? ? nil : AST::Types::Union.build(types: false_types)
        ]
      end

      def type_case_select0(type, klass)
        instance_type = factory.instance_type(klass)

        case type
        when AST::Types::Union
          truthy_types = [] # :Array[AST::Types::t]
          falsy_types = [] #: Array[AST::Types::t]

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
          if ty == type
            [[type], [type]]
          else
            type_case_select0(ty, klass)
          end

        when AST::Types::Any, AST::Types::Top, AST::Types::Var
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
          # There are four possible relations between `type` and `instance_type`
          #
          # ```ruby
          # case object      # object: T
          # when K           # K: singleton(K)
          # when ...
          # end
          # ````
          #
          # 1. T <: K && K <: T (T == K, T = Integer, K = Numeric)
          # 2. T <: K           (example: T = Integer, K = Numeric)
          # 3. K <: T           (example: T = Numeric, K = Integer)
          # 4. none of the above (example: T = String, K = Integer)

          if subtyping?(sub_type: type, super_type: instance_type)
            # 1 or 2. Satisfies the condition, no narrowing because `type` is already more specific than/equals to `instance_type`
            [
              [type],
              []
            ]
          else
            if subtyping?(sub_type: instance_type, super_type: type)
              # 3. Satisfied the condition, narrows to `instance_type`, but cannot remove it from *falsy* list
              [
                [instance_type],
                [type]
              ]
            else
              # 4
              [
                [],
                [type]
              ]
            end
          end
        end
      end

      def no_subtyping?(sub_type:, super_type:)
        relation = Subtyping::Relation.new(sub_type: sub_type, super_type: super_type)
        result = subtyping.check(relation, constraints: Subtyping::Constraints.empty, self_type: AST::Types::Self.instance, instance_type: AST::Types::Instance.instance, class_type: AST::Types::Class.instance)

        if result.failure?
          result
        end
      end

      def subtyping?(sub_type:, super_type:)
        !no_subtyping?(sub_type: sub_type, super_type: super_type)
      end

      def try_convert(type, method)
        if shape = subtyping.builder.shape(type, public_only: true, config: config)
          if entry = shape.methods[method]
            method_type = entry.method_types.find do |method_type|
              method_type.type.params.optional?
            end

            method_type.type.return_type if method_type
          end
        end
      end
    end
  end
end
