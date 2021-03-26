module Steep
  module TypeInference
    class Logic
      class Result
        attr_reader :nodes

        def initialize(nodes = [])
          @nodes = Set[].compare_by_identity.merge(nodes)
        end

        def +(other)
          Result.new(nodes + other.nodes)
        end

        def merge(nodes)
          Result.new(self.nodes + nodes)
        end

        def vars
          vars = Set[]

          nodes.each do |node|
            case node.type
            when :lvar, :lvasgn
              vars << node.children[0]
            end
          end

          vars
        end
      end

      attr_reader :subtyping

      def initialize(subtyping:)
        @subtyping = subtyping
      end

      def nodes(node:)
        case node.type
        when :lvasgn
          rhs = node.children[1]
          t, f = nodes(node: rhs)

          [
            t.merge([node]),
            f.merge([node])
          ]

        when :masgn
          lhs, rhs = node.children

          lt, lf = nodes(node: lhs)
          rt, rf = nodes(node: rhs)

          [
            (lt + rt).merge([node]),
            (lf + rf).merge([node])
          ]

        when :mlhs
          nodes = [node]

          node.children.each do |child|
            case child.type
            when :lvasgn
              nodes << child
            when :splat
              if node.children[0].type == :lvasgn
                nodes << child
                nodes << child.children[0]
              end
            end
          end

          [
            Result.new(nodes),
            Result.new(nodes)
          ]

        when :and
          lhs, rhs = node.children

          lt, _ = nodes(node: lhs)
          rt, _ = nodes(node: rhs)

          [
            Result.new([node]) + lt + rt,
            Result.new([node])
          ]

        when :or
          lhs, rhs = node.children

          _, lf = nodes(node: lhs)
          _, rf = nodes(node: rhs)

          [
            Result.new([node]),
            Result.new([node]) + lf + rf
          ]

        when :begin
          nodes(node: node.children.last)

        else
          [
            Result.new([node]),
            Result.new([node])
          ]
        end
      end

      def environments(truthy_vars:, falsey_vars:, lvar_env:)
        truthy_hash = lvar_env.assigned_types.dup
        falsey_hash = lvar_env.assigned_types.dup

        (truthy_vars + falsey_vars).each do |var|
          type = lvar_env[var]
          truthy_type, falsey_type = partition_union(type)

          if truthy_vars.include?(var)
            truthy_hash[var] = LocalVariableTypeEnv::Entry.new(type: truthy_type)
          end

          if falsey_vars.include?(var)
            falsey_hash[var] = LocalVariableTypeEnv::Entry.new(type: falsey_type)
          end
        end

        [
          lvar_env.except(truthy_vars).update(assigned_types: truthy_hash),
          lvar_env.except(falsey_vars).update(assigned_types: falsey_hash)
        ]
      end

      def partition_union(type)
        case type
        when AST::Types::Union
          falsey_types, truthy_types = type.types.partition do |type|
            case type
            when AST::Types::Nil
              true
            when AST::Types::Literal
              type.value == false
            end
          end

          [
            truthy_types.empty? ? AST::Types::Bot.new : AST::Types::Union.build(types: truthy_types),
            falsey_types.empty? ? AST::Types::Bot.new : AST::Types::Union.build(types: falsey_types)
          ]
        when AST::Types::Any, AST::Types::Top, AST::Types::Boolean, AST::Types::Void
          [type, type]
        else
          [type, AST::Types::Bot.new]
        end
      end
    end
  end
end
