module Steep
  module TypeInference
    class MultipleAssignment
      Assignments = _ = Struct.new(:rhs_type, :optional, :leading_assignments, :trailing_assignments, :splat_assignment, keyword_init: true) do
        # @implements Assignments

        def each(&block)
          if block
            leading_assignments.each(&block)
            if sp = splat_assignment
              yield sp
            end
            trailing_assignments.each(&block)
          else
            enum_for :each
          end
        end
      end

      def expand(mlhs, rhs_type, optional)
        lhss = mlhs.children

        case rhs_type
        when AST::Types::Tuple
          expand_tuple(lhss.dup, rhs_type, rhs_type.types.dup, optional)
        when AST::Types::Name::Instance
          if AST::Builtin::Array.instance_type?(rhs_type)
            expand_array(lhss.dup, rhs_type, optional)
          end
        when AST::Types::Any
          expand_any(lhss, rhs_type, AST::Builtin.any_type, optional)
        end
      end

      def expand_tuple(lhss, rhs_type, tuples, optional)
        # @type var leading_assignments: Array[node_type_pair]
        leading_assignments = []
        # @type var trailing_assignments: Array[node_type_pair]
        trailing_assignments = []
        # @type var splat_assignment: node_type_pair?
        splat_assignment = nil

        while !lhss.empty?
          first = lhss.first or raise

          case
          when first.type == :splat
            break
          else
            leading_assignments << [first, tuples.first || AST::Builtin.nil_type]
            lhss.shift
            tuples.shift
          end
        end

        while !lhss.empty?
          last = lhss.last or raise

          case
          when last.type == :splat
            break
          else
            trailing_assignments << [last, tuples.last || AST::Builtin.nil_type]
            lhss.pop
            tuples.pop
          end
        end

        case lhss.size
        when 0
          # nop
        when 1
          splat_assignment = [lhss.first || raise, AST::Types::Tuple.new(types: tuples)]
        else
          raise
        end

        Assignments.new(
          rhs_type: rhs_type,
          optional: optional,
          leading_assignments: leading_assignments,
          trailing_assignments: trailing_assignments,
          splat_assignment: splat_assignment
        )
      end

      def expand_array(lhss, rhs_type, optional)
        element_type = rhs_type.args[0] or raise

        # @type var leading_assignments: Array[node_type_pair]
        leading_assignments = []
        # @type var trailing_assignments: Array[node_type_pair]
        trailing_assignments = []
        # @type var splat_assignment: node_type_pair?
        splat_assignment = nil

        while !lhss.empty?
          first = lhss.first or raise

          case
          when first.type == :splat
            break
          else
            leading_assignments << [first, AST::Builtin.optional(element_type)]
            lhss.shift
          end
        end

        while !lhss.empty?
          last = lhss.last or raise

          case
          when last.type == :splat
            break
          else
            trailing_assignments << [last, AST::Builtin.optional(element_type)]
            lhss.pop
          end
        end

        case lhss.size
        when 0
          # nop
        when 1
          splat_assignment = [
            lhss.first || raise,
            AST::Builtin::Array.instance_type(element_type)
          ]
        else
          raise
        end

        Assignments.new(
          rhs_type: rhs_type,
          optional: optional,
          leading_assignments: leading_assignments,
          trailing_assignments: trailing_assignments,
          splat_assignment: splat_assignment
        )
      end

      def expand_any(nodes, rhs_type, element_type, optional)
        # @type var leading_assignments: Array[node_type_pair]
        leading_assignments = []
        # @type var trailing_assignments: Array[node_type_pair]
        trailing_assignments = []
        # @type var splat_assignment: node_type_pair?
        splat_assignment = nil

        array = leading_assignments

        nodes.each do |node|
          case node.type
          when :splat
            splat_assignment = [node, AST::Builtin::Array.instance_type(element_type)]
            array = trailing_assignments
          else
            array << [node, element_type]
          end
        end

        Assignments.new(
          rhs_type: rhs_type,
          optional: optional,
          leading_assignments: leading_assignments,
          trailing_assignments: trailing_assignments,
          splat_assignment: splat_assignment
        )
      end

      def hint_for_mlhs(mlhs, env)
        case mlhs.type
        when :mlhs
          types = mlhs.children.map do |node|
            hint_for_mlhs(node, env) or return
          end
          AST::Types::Tuple.new(types: types)
        when :lvasgn, :ivasgn, :gvasgn
          name = mlhs.children[0]
          
          unless TypeConstruction::SPECIAL_LVAR_NAMES.include?(name)
            env[name] || AST::Builtin.any_type
          else
            AST::Builtin.any_type
          end
        when :splat
          return
        else
          return
        end
      end
    end
  end
end
