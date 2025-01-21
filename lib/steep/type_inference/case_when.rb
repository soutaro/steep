module Steep
  module TypeInference
    class CaseWhen
      class WhenPatterns
        include NodeHelper

        attr_reader :logic, :initial_constr, :unreachable_clause, :pattern_results

        def initialize(logic, initial_constr, unreachable_clause, assignment_node)
          @logic = logic
          @initial_constr = initial_constr
          @unreachable_clause = unreachable_clause
          @assignment_node = assignment_node

          @pattern_results = []
        end

        def add_pattern(pat)
          test_node = pat.updated(:send, [pat, :===, assignment_node])

          latest_constr, unreachable_pattern = latest_result

          type, constr = yield(test_node, latest_constr, unreachable_pattern)
          truthy_result, falsy_result = logic.eval(env: latest_constr.context.type_env, node: test_node)

          pattern_results << [pat, truthy_result, falsy_result]
        end

        def latest_result
          if (_, truthy, falsy = pattern_results.last)
            [
              initial_constr.update_type_env { falsy.env },
              falsy.unreachable
            ]
          else
            [initial_constr, unreachable_clause]
          end
        end

        def body_result
          raise if pattern_results.empty?

          type_envs = pattern_results.map {|_, truthy, _| truthy.env }
          env = initial_constr.context.type_env.join(*type_envs)

          env = yield(env) || env

          [
            initial_constr.update_type_env { env },
            unreachable_clause || pattern_results.all? {|_, truthy, _| truthy.unreachable }
          ]
        end

        def falsy_result
          (_, _, falsy = pattern_results.last) or raise

          [
            initial_constr.update_type_env { falsy.env },
            unreachable_clause || falsy.unreachable
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

          body_constr, body_unreachable = when_pats.body_result() do |env|
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
            unreachable: body_unreachable
          )

          falsy_constr, falsy_unreachable = when_pats.falsy_result
          next_result = LogicTypeInterpreter::Result.new(
            type: AST::Builtin.any_type,    # Unused for falsy pattern
            env: falsy_constr.context.type_env,
            unreachable: falsy_unreachable
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
          clause_constr, unreachable = latest_result

          patterns, body, loc = deconstruct_when_node!(when_node)

          when_pats = WhenPatterns.new(
            logic,
            clause_constr,
            unreachable,
            assignment_node
          )

          body_result, next_result = yield(
            when_pats,
            patterns,
            body,
            loc
          )

          if body_result.unreachable
            if body_result.type.is_a?(AST::Types::Any) || initial_constr.no_subtyping?(sub_type: body_result.type, super_type: AST::Builtin.bottom_type)
              typing.add_error(
                Diagnostic::Ruby::UnreachableValueBranch.new(
                  node: when_node,
                  type: body_result.type,
                  location: loc.keyword
                )
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

        constr, unreachable = latest_result

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

        if unreachable
          if else_result.type.is_a?(AST::Types::Any) || initial_constr.no_subtyping?(sub_type: else_result.type, super_type: AST::Builtin.bottom_type)
            typing.add_error(
              Diagnostic::Ruby::UnreachableValueBranch.new(
                node: else_node || node,
                type: else_result.type,
                location: else_loc
              )
            )
          end
        end
      end

      def latest_result
        if (_, falsy_result = clause_results.last)
          [
            initial_constr.update_type_env { falsy_result.env },
            falsy_result.unreachable
          ]
        else
          [initial_constr, false]
        end
      end

      def result
        results = clause_results.filter_map do |body, _|
          unless body.unreachable
            body
          end
        end
        next_constr, next_clause_unreachable = latest_result

        unless next_clause_unreachable
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
          if (call = initial_constr.typing.method_calls[value_node]).is_a?(MethodCall::Typed)
            if env[value_node]
              env.merge(pure_method_calls: { value_node => [call, env[var_name]] })
            end
          end
        end
      end
    end
  end
end
