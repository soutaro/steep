module Steep
  module TypeInference
    class PatternMatching
      class Clause < Struct.new(:truthy_result, :falsy_result, :body_pair)
      end

      attr_reader :initial, :clauses, :last_result

      def initialize(initial:)
        @initial = initial
        @clauses = []
      end

      def match_clause(pattern)
        case pattern.type
        when :array_pattern
        when :match_as
        when :const_pattern
        else

        end
      end

      def else_clause()
        @else_clause_result = pair = yield last_result.env
      end

      def result
        types = [] #: Array[AST::Types::t]
        envs = [] #: Array[TypeEnv]

        clauses.each do |clause|
          types << clause.body_result.type
          envs << clause.body_result.constr.context.type_env
        end
        if else_result = @else_clause_result
          types << else_result.type
          envs << else_result.constr.context.type_env
        end

        type = AST::Types::Union.build(types: types)
        env = initial.constr.context.type_env.join(*envs)

        TypeConstruction::Pair.new(type: type, constr: initial.constr.update_type_env { env })
      end

      def last_result
        if last_clause = clauses.last
          last_clause.falsy_result
        else
          LogicTypeInterpreter::Result.new(
            env: initial.constr.context.type_env,
            type: AST::Builtin.any_type,
            unreachable: false
          )
        end
      end
    end
  end
end
