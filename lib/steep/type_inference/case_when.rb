module Steep
  module TypeInference
    class CaseWhen
      class WhenPatterns
        include NodeHelper

        attr_reader :logic, :initial_constr, :clause_verdict, :pattern_results

        # `clause_verdict` is the emptiness of the clause before its patterns: the previous clauses may have exhausted the value
        def initialize(logic, initial_constr, clause_verdict, assignment_node)
          @logic = logic
          @initial_constr = initial_constr
          @clause_verdict = clause_verdict
          @assignment_node = assignment_node

          @pattern_results = []
        end

        def add_pattern(pat)
          test_node = pat.updated(:send, [pat, :===, assignment_node])

          latest_constr, pattern_verdict = latest_result

          yield(test_node, latest_constr, pattern_verdict)
          truthy_result, falsy_result = logic.eval(env: latest_constr.context.type_env, node: test_node)

          pattern_results << [pat, truthy_result, falsy_result]
        end

        def latest_result
          if (_, _, falsy = pattern_results.last)
            [
              initial_constr.update_type_env { falsy.env },
              clause_verdict & falsy.verdict
            ]
          else
            [initial_constr, clause_verdict]
          end
        end

        def body_result
          raise if pattern_results.empty?

          type_envs = pattern_results.map {|_, truthy, _| truthy.env }
          env = initial_constr.context.type_env.join(*type_envs)

          env = yield(env) || env

          # The body is reachable when one of the patterns matches
          patterns_verdict = pattern_results.inject(SetTheoretic::Verdict.empty) {|verdict, (_, truthy, _)| verdict | truthy.verdict }

          [
            initial_constr.update_type_env { env },
            clause_verdict & patterns_verdict
          ]
        end

        def falsy_result
          (_, _, falsy = pattern_results.last) or raise

          [
            initial_constr.update_type_env { falsy.env },
            clause_verdict & falsy.verdict
          ]
        end

        def assignment_node()
          clone_node(@assignment_node)
        end
      end

      include NodeHelper
      extend NodeHelper

      def self.type_check(constr, node, logic, hint:, condition:)
        case_when = new(node, logic) do |condition_node|
          constr.synthesize(condition_node)
        end

        case_when.when_clauses() do |when_pats, patterns, body_node, loc|
          patterns.each do |pat|
            when_pats.add_pattern(pat) {|test, constr| constr.synthesize(test) }
          end

          body_constr, body_verdict = when_pats.body_result() do |env|
            case_when.propagate_value_node_type(env)
          end

          if body_node
            body_constr = body_constr.for_branch(body_node)
            type, body_constr = body_constr.synthesize(body_node, hint: hint, condition: condition)
          else
            type = AST::Builtin.nil_type
          end

          body_result = LogicTypeInterpreter::Result.new(
            type: type,
            env: body_constr.context.type_env,
            verdict: body_verdict
          )

          falsy_constr, falsy_verdict = when_pats.falsy_result
          next_result = LogicTypeInterpreter::Result.new(
            type: AST::Builtin.any_type,    # Unused for falsy pattern
            env: falsy_constr.context.type_env,
            verdict: falsy_verdict
          )

          [body_result, next_result]
        end

        case_when.else_clause do |else_node, constr|
          constr.synthesize(else_node, hint: hint, condition: condition)
        end

        case_when.result()
      end

      attr_reader :location, :node, :condition_node, :when_nodes, :else_node
      attr_reader :initial_constr, :logic, :clause_results, :else_result
      attr_reader :assignment_node, :value_node, :var_name

      def initialize(node, logic)
        @node = node

        condition_node, when_nodes, else_node, location = deconstruct_case_node!(node)
        condition_node or raise "CaseWhen works for case-when syntax with condition node"

        @condition_node = condition_node
        @when_nodes = when_nodes
        @else_node = else_node
        @location = location
        @logic = logic
        @clause_results = []

        type, constr = yield(condition_node)

        @var_name = "__case_when:#{SecureRandom.alphanumeric(5)}__".to_sym
        @value_node, @assignment_node = rewrite_condition_node(var_name, condition_node)

        @initial_constr = constr.update_type_env do |env|
          env.merge(local_variable_types: { var_name => [type, nil] })
        end
      end

      def when_clauses()
        when_nodes.each do |when_node|
          clause_constr, clause_verdict = latest_result

          patterns, body, loc = deconstruct_when_node!(when_node)

          when_pats = WhenPatterns.new(
            logic,
            clause_constr,
            clause_verdict,
            assignment_node
          )

          body_result, next_result = yield(
            when_pats,
            patterns,
            body,
            loc
          )

          unless body_result.verdict.inhabited?
            if body_result.type.is_a?(AST::Types::Any) || initial_constr.no_subtyping?(sub_type: body_result.type, super_type: AST::Builtin.bottom_type)
              typing.add_error(
                Diagnostic::Ruby.unreachable_value_branch(
                  body_result.verdict,
                  node: when_node,
                  type: body_result.type,
                  location: loc.keyword
                ) || raise
              )
            end
          end

          clause_results << [body_result, next_result]
        end
      end

      def else_clause()
        unless else_loc = has_else_clause?
          return
        end

        constr, verdict = latest_result

        constr = constr.update_type_env do |env|
          propagate_value_node_type(env) || env
        end

        @else_result =
          if else_node
            yield(else_node, constr)
          else
            TypeConstruction::Pair.new(type: AST::Builtin.nil_type, constr: constr)
          end

        else_result or raise

        unless verdict.inhabited?
          if else_result.type.is_a?(AST::Types::Any) || initial_constr.no_subtyping?(sub_type: else_result.type, super_type: AST::Builtin.bottom_type)
            typing.add_error(
              Diagnostic::Ruby.unreachable_value_branch(
                verdict,
                node: else_node || node,
                type: else_result.type,
                location: else_loc
              ) || raise
            )
          end
        end
      end

      def latest_result
        if (_, falsy_result = clause_results.last)
          [
            initial_constr.update_type_env { falsy_result.env },
            falsy_result.verdict
          ]
        else
          [initial_constr, SetTheoretic::Verdict.inhabited]
        end
      end

      def result
        results = clause_results.filter_map do |body, _|
          unless body.unreachable
            body
          end
        end
        next_constr, next_clause_verdict = latest_result

        unless next_clause_verdict.empty?
          if else_result
            results << LogicTypeInterpreter::Result.new(
              type: else_result.type,
              env: else_result.context.type_env,
              unreachable: false    # Unused
            )
          else
            results << LogicTypeInterpreter::Result.new(
              type: AST::Builtin.nil_type,
              env: next_constr.context.type_env,
              unreachable: false
            )
          end
        end

        results.reject! { _1.type.is_a?(AST::Types::Bot) }

        types = results.map {|result| result.type }
        envs = results.map {|result| result.env }

        [
          types,
          envs
        ]
      end

      def has_else_clause?
        location.else
      end

      def typing
        logic.typing
      end

      def rewrite_condition_node(var_name, node)
        case node.type
        when :lvasgn
          name, rhs = node.children
          value, rhs = rewrite_condition_node(var_name, rhs)
          [value, node.updated(nil, [name, rhs])]
        when :lvar
          name, = node.children
          [
            nil,
            node.updated(:lvasgn, [name, node.updated(:lvar, [var_name])])
          ]
        when :begin
          *children, last = node.children
          value_node, last = rewrite_condition_node(var_name, last)
          [
            value_node,
            node.updated(nil, children.push(last))
          ]
        else
          [
            node,
            node.updated(:lvar, [var_name])
          ]
        end
      end

      def propagate_value_node_type(env)
        if value_node
          if initial_constr.typing.method_calls[value_node].is_a?(MethodCall::Typed)
            if env[value_node]
              logic.refine_pure_call(env, value_node, env[var_name] || raise)
            end
          end
        end
      end
    end
  end
end
