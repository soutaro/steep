module Steep
  module TypeInference
    class PatternMatching
      class Clause < Struct.new(:truthy_result, :falsy_result, :body_pair)
      end

      attr_reader :initial_result, :clauses, :node, :logic

      def initialize(initial_result:, node:, logic:)
        @initial_result = initial_result
        @node = node
        @logic = logic
        @clauses = []
      end

      def match_clause(pattern)
        case pattern.type
        when :array_pattern
          raise pattern.inspect
        when :match_as
          raise pattern.inspect
        when :const_pattern
          raise pattern.inspect
        else
          var_name = :"steep:pattern_matching[#{SecureRandom.alphanumeric(4)}]"

          var_cond, value_node = transform_condition_node(node, var_name)
          constr = initial_result.constr.update_type_env {|env| env.assign_local_variable(var_name, initial_result.type, nil) }

          pattern_node = pattern.updated(:send, [pattern, :===, var_cond])
          pattern_type, constr = constr.synthesize(pattern_node, condition: true)

          truthy, falsy = logic.eval(node: pattern_node, env: constr.context.type_env)
          truthy = truthy.update_env { propagate_type_env(var_name, value_node, truthy.env) }
          falsy = falsy.update_env { propagate_type_env(var_name, value_node, falsy.env) }

          pair = yield(truthy.env)

          clauses << Clause.new(truthy, falsy, pair)

          pair
        end
      end

      def else_clause()
        @else_clause_result = pair = yield last_result.env
      end

      def result
        types = [] #: Array[AST::Types::t]
        envs = [] #: Array[TypeEnv]

        clauses.each do |clause|
          types << clause.body_pair.type
          envs << clause.body_pair.constr.context.type_env
        end
        if else_result = @else_clause_result
          types << else_result.type
          envs << else_result.constr.context.type_env
        end

        type = AST::Types::Union.build(types: types)
        env = initial_result.constr.context.type_env.join(*envs)

        TypeConstruction::Pair.new(type: type, constr: initial_result.constr.update_type_env { env })
      end

      def last_result
        if last_clause = clauses.last
          last_clause.falsy_result
        else
          LogicTypeInterpreter::Result.new(
            env: initial_result.constr.context.type_env,
            type: AST::Builtin.any_type,
            unreachable: false
          )
        end
      end

      def transform_condition_node(node, var_name)
        case node.type
        when :lvasgn
          name, rhs = node.children
          rhs, value_node = transform_condition_node(rhs, var_name)
          [node.updated(nil, [name, rhs]), value_node]
        when :begin
          *children, last = node.children
          last, value_node = transform_condition_node(last, var_name)
          [node.updated(nil, children.push(last)), value_node]
        else
          var_node = node.updated(:lvar, [var_name])
          [var_node, node]
        end
      end

      def propagate_type_env(source, dest, env)
        source_type = env[source] or raise

        if dest.type == :lvar
          var_name = dest.children[0] #: Symbol
          env.assign_local_variable(var_name, source_type, nil)
        else
          if env[dest]
            env.replace_pure_call_type(dest, source_type)
          else
            env
          end
        end
      end
    end
  end
end
