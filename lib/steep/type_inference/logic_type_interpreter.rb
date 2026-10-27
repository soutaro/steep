module Steep
  module TypeInference
    class LogicTypeInterpreter
      class Result
        attr_reader :env

        attr_reader :type

        # `true` when the verdict is `empty`
        attr_accessor :unreachable

        # The emptiness of the branch
        attr_accessor :verdict

        def initialize(env:, type:, unreachable: false, verdict: nil)
          verdict ||= unreachable ? SetTheoretic::Verdict.empty : SetTheoretic::Verdict.inhabited
          @env = env
          @type = type
          @unreachable = verdict.empty?
          @verdict = verdict
        end

        def ==(other)
          other.is_a?(Result) && other.env == env && other.type == type && other.unreachable == unreachable && other.verdict == verdict
        end

        alias eql? ==

        def hash
          self.class.hash ^ env.hash ^ type.hash ^ verdict.hash
        end

        def update_env
          env = yield()
          Result.new(type: type, env: env, verdict: verdict)
        end

        def update_type
          Result.new(type: yield, env: env, verdict: verdict)
        end

        def unreachable!
          self.unreachable = true
          self.verdict = SetTheoretic::Verdict.empty
          self
        end

        # `true` if the branch is unreachable as long as the class hierarchy is what the RBS environment declares
        def unreachable_in_rbs?
          verdict.empty_in_rbs?
        end
      end

      class RecordDiscriminant < Struct.new(:name, :entries, keyword_init: true)
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

      def emptiness
        subtyping.emptiness
      end

      def simplifier
        subtyping.simplifier
      end

      def bounds
        config.variable_bounds
      end

      # The values of `type` that are in `predicate` and the ones that are not, with the verdicts of the two branches
      #
      # `negative` is the type the falsy branch excludes, `predicate` unless given.
      def narrow(type, predicate, negative: predicate)
        negation = AST::Types::Negation.build(type: negative)

        truthy_type = simplifier.intersect(type, predicate, bounds: bounds, candidates: [type])
        falsy_type = simplifier.intersect(type, negation, bounds: bounds, candidates: [type])
        truthy_verdict = emptiness.check(AST::Types::Intersection.build(types: [type, predicate]), mode: :inhabitation, bounds: bounds)
        falsy_verdict = emptiness.check(AST::Types::Intersection.build(types: [type, negation]), mode: :inhabitation, bounds: bounds)

        [truthy_type, falsy_type, truthy_verdict, falsy_verdict]
      end

      # The truthy values of `type` and the falsy ones
      #
      # `bool`, the logic types, and `untyped` stay on both sides as they are, instead of `true`, `false`, and
      # `nil | false`, so that the variables of type `bool` keep their type and `untyped && x` stays `untyped`.
      def truthiness(type)
        members = factory.flatten_union(factory.deep_expand_alias(type) || type)
        opaque, rest = members.partition do |member|
          member.is_a?(AST::Types::Boolean) || member.is_a?(AST::Types::Logic::Base) || member.is_a?(AST::Types::Any)
        end

        if opaque.empty?
          narrow(type, AST::Types::Negation.build(type: FALSY))
        else
          opaque_type = AST::Types::Union.build(types: opaque)
          if rest.empty?
            [opaque_type, opaque_type, SetTheoretic::Verdict.inhabited, SetTheoretic::Verdict.inhabited]
          else
            truthy_type, falsy_type, truthy_verdict, falsy_verdict = narrow(AST::Types::Union.build(types: rest), AST::Types::Negation.build(type: FALSY))
            [
              truthy_verdict.empty? ? opaque_type : AST::Types::Union.build(types: [truthy_type, opaque_type]),
              falsy_verdict.empty? ? opaque_type : AST::Types::Union.build(types: [falsy_type, opaque_type]),
              SetTheoretic::Verdict.inhabited,
              SetTheoretic::Verdict.inhabited
            ]
          end
        end
      end

      # Narrows `type` by `is_a?(klass)`: the instances of the class are `klass[untyped, ...]` on the truthy branch and
      # `klass[top, ...]` on the falsy one
      def type_case(type, klass)
        # One lookup of the type parameters: `Definition#type_params` validates them on every call
        arity = factory.definition_builder.build_singleton(klass).type_params.size
        positive = AST::Types::Name::Instance.new(name: klass, args: Array.new(arity, AST::Builtin.any_type))
        negative = AST::Types::Name::Instance.new(name: klass, args: Array.new(arity, AST::Types::Top.instance))
        narrow(type, positive, negative: negative)
      end

      # The literal type of a literal node; `nil` for the other nodes
      def literal_type(node)
        case node.type
        when :nil
          AST::Builtin.nil_type
        when :true
          TRUE
        when :false
          FALSE
        when :int, :str, :sym
          AST::Types::Literal.new(value: node.children[0])
        end
      end

      def guess_type_from_method(node)
        if node.type == :send
          method = node.children[1]
          case method
          when :is_a?, :kind_of?, :instance_of?
            AST::Types::Logic::ReceiverIsArg.instance
          when :nil?
            AST::Types::Logic::ReceiverIsNil.instance
          when :!
            AST::Types::Logic::Not.instance
          when :===
            AST::Types::Logic::ArgIsReceiver.instance
          end
        end
      end

      TRUE = AST::Types::Literal.new(value: true)
      FALSE = AST::Types::Literal.new(value: false)
      BOOL = AST::Types::Boolean.instance
      BOT = AST::Types::Bot.instance
      UNTYPED = AST::Types::Any.instance

      # The falsy values
      FALSY = AST::Types::Union.build(types: [AST::Builtin.nil_type, FALSE])

      def eval(env:, node:)
        evaluate_node(env: env, node: node)
      end

      def evaluate_node(env:, node:, type: typing.type_of(node: node))
        if type.is_a?(AST::Types::Logic::Env)
          truthy_env = type.truthy
          falsy_env = type.falsy

          truthy_type, falsy_type, truthy_verdict, falsy_verdict = truthiness(type.type)

          return [
            Result.new(env: truthy_env, type: truthy_verdict.empty? ? TRUE : truthy_type, verdict: truthy_verdict),
            Result.new(env: falsy_env, type: falsy_verdict.empty? ? FALSE : falsy_type, verdict: falsy_verdict)
          ]
        end

        if type.is_a?(AST::Types::Bot) || type.is_a?(AST::Types::Void)
          return [
            Result.new(env: env, type: BOT, unreachable: true),
            Result.new(env: env, type: BOT, unreachable: true),
          ]
        end

        case node.type
        when :lvar
          name = node.children[0]
          truthy_type, falsy_type, truthy_verdict, falsy_verdict = truthiness(type)

          truthy_result =
            if truthy_verdict.empty?
              Result.new(type: type, env: env, verdict: truthy_verdict)
            else
              Result.new(type: truthy_type, env: env.refine_types(local_variable_types: { name => truthy_type }), verdict: truthy_verdict)
            end

          falsy_result =
            if falsy_verdict.empty?
              Result.new(type: type, env: env, verdict: falsy_verdict)
            else
              Result.new(type: falsy_type, env: env.refine_types(local_variable_types: { name => falsy_type }), verdict: falsy_verdict)
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
          truthy_type, _, truthy_verdict, _ = truthiness(type)

          truthy_result, falsy_result = evaluate_node(
            env: truthy_receiver.env,
            node: node.updated(:send),
            type: truthy_verdict.empty? ? type : truthy_type
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
            receiver, *_ = node.children
            receiver_type = typing.type_of(node: receiver) if receiver

            if env[receiver] && receiver_type.is_a?(AST::Types::Union)
              result = evaluate_union_method_call(node: node, type: type, env: env, receiver: receiver, receiver_type: receiver_type)
              if result
                truthy_result = result[0] unless result[0].unreachable
                falsy_result = result[1] unless result[1].unreachable
              end
            end

            truthy_result ||= Result.new(type: type, env: env, unreachable: false)
            falsy_result ||= Result.new(type: type, env: env, unreachable: false)

            truthy_type, falsy_type, truthy_verdict, falsy_verdict = truthiness(type)

            if truthy_verdict.empty?
              truthy_result = truthy_result.update_type { BOT }.unreachable!
            else
              truthy_result = Result.new(type: truthy_type, env: truthy_result.env, verdict: truthy_result.verdict & truthy_verdict)
            end

            if falsy_verdict.empty?
              falsy_result = falsy_result.update_type { BOT }.unreachable!
            else
              falsy_result = Result.new(type: falsy_type, env: falsy_result.env, verdict: falsy_result.verdict & falsy_verdict)
            end

            if truthy_result.env[node] && falsy_result.env[node]
              unless truthy_verdict.empty?
                truthy_result = Result.new(type: truthy_type, env: refine_pure_call(truthy_result.env, node, truthy_type), verdict: truthy_result.verdict)
              end

              unless falsy_verdict.empty?
                falsy_result = Result.new(type: falsy_type, env: refine_pure_call(falsy_result.env, node, falsy_type), verdict: falsy_result.verdict)
              end
            end

            return [truthy_result, falsy_result]
          end
        end

        truthy_type, falsy_type, truthy_verdict, falsy_verdict = truthiness(type)
        return [
          Result.new(type: truthy_verdict.empty? ? BOT : truthy_type, env: env, verdict: truthy_verdict),
          Result.new(type: falsy_verdict.empty? ? BOT : falsy_type, env: env, verdict: falsy_verdict)
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
            discriminant = record_discriminant(env, node)
            [
              refine_pure_call(env, node, truthy_type, discriminant),
              refine_pure_call(env, node, falsy_type, discriminant)
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
            truthy_receiver, falsy_receiver, truthy_verdict, falsy_verdict = narrow(receiver_type, AST::Builtin.nil_type)

            truthy_env, falsy_env = refine_node_type(
              env: env,
              node: receiver,
              truthy_type: truthy_verdict.empty? ? AST::Builtin.nil_type : truthy_receiver,
              falsy_type: falsy_verdict.empty? ? receiver_type : falsy_receiver
            )

            [
              Result.new(type: TRUE, env: truthy_env, verdict: truthy_verdict),
              Result.new(type: FALSE, env: falsy_env, verdict: falsy_verdict)
            ]
          end

        when AST::Types::Logic::ReceiverIsArg
          if receiver && (arg = arguments[0])
            receiver_type = typing.type_of(node: receiver)
            arg_type = factory.deep_expand_alias(typing.type_of(node: arg))

            if arg_type.is_a?(AST::Types::Name::Singleton)
              truthy_type, falsy_type, truthy_verdict, falsy_verdict = type_case(receiver_type, arg_type.name)
              truthy_env, falsy_env = refine_node_type(
                env: env,
                node: receiver,
                truthy_type: truthy_verdict.empty? ? factory.instance_type(arg_type.name) : truthy_type,
                falsy_type: falsy_verdict.empty? ? UNTYPED : falsy_type
              )

              [
                Result.new(type: TRUE, env: truthy_env, verdict: truthy_verdict),
                Result.new(type: FALSE, env: falsy_env, verdict: falsy_verdict)
              ]
            elsif (literal = literal_type(arg))
              # Literal equality: `receiver == literal`
              truthy_type, falsy_type, truthy_verdict, falsy_verdict = narrow(receiver_type, literal)
              truthy_env, falsy_env = refine_node_type(
                env: env,
                node: receiver,
                truthy_type: truthy_verdict.empty? ? BOT : truthy_type,
                falsy_type: falsy_verdict.empty? ? BOT : falsy_type
              )

              [
                Result.new(type: TRUE, env: truthy_env, verdict: truthy_verdict),
                Result.new(type: FALSE, env: falsy_env, verdict: falsy_verdict)
              ]
            end
          end

        when AST::Types::Logic::ArgIsReceiver
          if receiver && (arg = arguments[0])
            receiver_type = factory.deep_expand_alias(typing.type_of(node: receiver))
            arg_type = typing.type_of(node: arg)

            if receiver_type.is_a?(AST::Types::Name::Singleton)
              truthy_type, falsy_type, truthy_verdict, falsy_verdict = type_case(arg_type, receiver_type.name)
              truthy_env, falsy_env = refine_node_type(
                env: env,
                node: arg,
                truthy_type: truthy_verdict.empty? ? factory.instance_type(receiver_type.name) : truthy_type,
                falsy_type: falsy_verdict.empty? ? UNTYPED : falsy_type
              )

              [
                Result.new(type: TRUE, env: truthy_env, verdict: truthy_verdict),
                Result.new(type: FALSE, env: falsy_env, verdict: falsy_verdict)
              ]
            end
          end
        when AST::Types::Logic::ArgEqualsReceiver
          if receiver && (arg = arguments[0])
            arg_type = typing.type_of(node: arg)
            if (literal = literal_type(receiver))
              truthy_type, falsy_type, truthy_verdict, falsy_verdict = narrow(arg_type, literal)
              truthy_env, falsy_env = refine_node_type(
                env: env,
                node: arg,
                truthy_type: truthy_verdict.empty? ? BOT : truthy_type,
                falsy_type: falsy_verdict.empty? ? BOT : falsy_type
              )

              [
                Result.new(type: TRUE, env: truthy_env, verdict: truthy_verdict),
                Result.new(type: FALSE, env: falsy_env, verdict: falsy_verdict)
              ]
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

      def evaluate_union_method_call(node:, type:, env:, receiver:, receiver_type:)
        call_type = typing.call_of(node: node) rescue nil
        return unless call_type.is_a?(Steep::TypeInference::MethodCall::Typed)

        truthy_types = [] #: Array[AST::Types::t]
        falsy_types = [] #: Array[AST::Types::t]

        receiver_type.types.each do |type|
          if shape = subtyping.builder.shape(type, config)
            method = shape.methods[call_type.method_name] or raise
            method_type = method.method_types.find do |method_type|
              call_type.method_decls.any? {|decl| factory.method_type(decl.method_type) == method_type }
            end
            if method_type
              return_type = method_type.type.return_type
              _, _, truthy_verdict, falsy_verdict = truthiness(return_type)
              truthy_types << type unless truthy_verdict.empty?
              falsy_types << type unless falsy_verdict.empty?
              next
            end
          end

          truthy_types << type
          falsy_types << type
        end

        truthy_type = truthy_types.empty? ? BOT : AST::Types::Union.build(types: truthy_types)
        falsy_type = falsy_types.empty? ? BOT : AST::Types::Union.build(types: falsy_types)

        truthy_env, falsy_env = refine_node_type(
          env: env,
          node: receiver,
          truthy_type: truthy_type,
          falsy_type: falsy_type
        )

        return [
          Result.new(type: type, env: truthy_env, unreachable: truthy_type.nil?),
          Result.new(type: type, env: falsy_env, unreachable: falsy_type.nil?)
        ]
      end

      def refine_pure_call(env, node, type, discriminant = record_discriminant(env, node))
        lvar_types = {} #: Hash[Symbol, AST::Types::t]
        if discriminant && (narrowed = narrow_record_receiver(discriminant, type))
          lvar_types[discriminant.name] = narrowed
        end
        env.narrow_types(local_variable_types: lvar_types, pure_call_types: { node => type })
      end

      # Not expanded inside `narrow_record_receiver` because that would repeat the same expansion for each of the truthy and falsy branches.
      def record_discriminant(env, node)
        receiver, method, key_node, *rest = node.children
        return unless method == :[] && rest.empty? && receiver&.type == :lvar
        return unless key_node && (key_node.type == :sym || key_node.type == :str)

        name = receiver.children[0] #: Symbol
        key = key_node.children[0] #: Symbol | String
        return if TypeConstruction::SPECIAL_LVAR_NAMES.include?(name)
        members = union_members(env[name]) or return

        entries = members.map do |member|
          [member, discriminant_key_types(member, key)] #: [AST::Types::t, Array[AST::Types::t]?]
        end

        RecordDiscriminant.new(name: name, entries: entries)
      end

      def discriminant_key_types(member, key)
        record = factory.deep_expand_alias(member)
        return unless record.is_a?(AST::Types::Record) && record.elements.key?(key)

        key_type = record.elements.fetch(key)
        key_types = factory.flatten_union(factory.deep_expand_alias(key_type) || key_type)
        # Dropping members whose discriminant is non-literal (e.g. `String`) would wrongly exclude values that may still match.
        return unless key_types.all? {|t| t.is_a?(AST::Types::Literal) || t.is_a?(AST::Types::Nil) }

        key_types |= [AST::Builtin.nil_type] if record.optional?(key)
        key_types
      end

      def narrow_record_receiver(discriminant, type)
        return BOT if type.is_a?(AST::Types::Bot)

        type_expanded = factory.flatten_union(factory.deep_expand_alias(type) || type)

        kept = discriminant.entries.select do |_, key_types|
          key_types.nil? || !disjoint?(key_types, type_expanded)
        end

        return if kept.size == discriminant.entries.size
        kept.empty? ? BOT : AST::Types::Union.build(types: kept.map(&:first))
      end

      def union_members(type, visited = Set.new)
        case type
        when AST::Types::Union
          type.types.flat_map {|member| union_members(member, visited) || [member] }
        when AST::Types::Name::Alias
          return if visited.include?(type.name)
          union_members(factory.expand_alias(type), visited | [type.name])
        end
      end

      def disjoint?(key_types, type_expanded)
        key_types.product(type_expanded).none? do |k, t|
          subtyping?(sub_type: k, super_type: t) || subtyping?(sub_type: t, super_type: k)
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

      # Narrows `type` by `is_a?(klass)`: the truthy type and the falsy type, `nil` when the branch is unreachable
      def type_case_select(type, klass)
        truthy_type, falsy_type, truthy_verdict, falsy_verdict = type_case(type, klass)

        [
          truthy_verdict.empty? ? nil : truthy_type,
          falsy_verdict.empty? ? nil : falsy_type
        ]
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
        if shape = subtyping.builder.shape(type, config)
          if entry = shape.methods[method]
            method_type = entry.method_types.find do |method_type|
              method_type.type.params.nil? ||
                method_type.type.params.optional?
            end

            method_type.type.return_type if method_type
          end
        end
      end
    end
  end
end
