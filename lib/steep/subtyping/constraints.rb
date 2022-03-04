module Steep
  module Subtyping
    class Constraints
      class UnsatisfiedInvariantError < StandardError
        attr_reader :constraints
        attr_reader :reason

        def initialize(reason:, constraints:)
          @reason = reason
          @constraints = constraints
          super "Invalid constraint: reason=#{reason.message}, constraints=#{constraints.to_s}"
        end

        class VariablesUnknownsNotDisjoint
          attr_reader :vars

          def initialize(vars:)
            @vars = vars
          end

          def message
            "Variables and unknowns should be disjoint (#{vars})"
          end
        end

        class VariablesFreeVariablesNotDisjoint
          attr_reader :var
          attr_reader :lower_bound
          attr_reader :upper_bound

          def initialize(var: nil, lower_bound: nil, upper_bound: nil)
            @var = var
            @lower_bound = lower_bound
            @upper_bound = upper_bound
          end

          def message
            "Variables and FV(constraints) should be disjoint (#{var}, #{lower_bound}, #{upper_bound})"
          end
        end

        class UnknownsFreeVariableNotDisjoint
          attr_reader :var
          attr_reader :upper_bound
          attr_reader :lower_bound

          def initialize(var:, lower_bound:, upper_bound:)
            @var = var
            @lower_bound = lower_bound
            @upper_bound = upper_bound
          end

          def message
            "Unknowns and FV(constraints) should be disjoint (#{var}, #{lower_bound}, #{upper_bound})"
          end
        end
      end

      class UnsatisfiableConstraint < StandardError
        attr_reader :var
        attr_reader :sub_type
        attr_reader :super_type
        attr_reader :result

        def initialize(var:, sub_type:, super_type:, result:)
          @var = var
          @sub_type = sub_type
          @super_type = super_type
          @result = result

          super "Unsatisfiable constraint on #{var}: #{sub_type} <: #{super_type}"
        end
      end

      attr_reader :dictionary
      attr_reader :vars

      def initialize(unknowns:)
        @dictionary = {}
        @vars = Set.new

        unknowns.each do |var|
          dictionary[var] = [Set.new, Set.new, Set.new]
        end
      end

      def self.empty
        new(unknowns: [])
      end

      def add_var(*vars)
        vars.each do |var|
          self.vars << var
        end

        unless Set.new(vars).disjoint?(unknowns)
          raise UnsatisfiedInvariantError.new(
            reason: UnsatisfiedInvariantError::VariablesUnknownsNotDisjoint.new(vars: vars),
            constraints: constraints
          )
        end
      end

      def add(var, sub_type: nil, super_type: nil, skip: false)
        subs, supers, skips = dictionary[var]

        if sub_type.is_a?(AST::Types::Logic::Base)
          sub_type = AST::Builtin.bool_type
        end

        if super_type.is_a?(AST::Types::Logic::Base)
          super_type = AST::Builtin.bool_type
        end

        if super_type && !super_type.is_a?(AST::Types::Top)
          type = eliminate_variable(super_type, to: AST::Types::Top.new)
          supers << type
          skips << type if skip
        end

        if sub_type && !sub_type.is_a?(AST::Types::Bot)
          type = eliminate_variable(sub_type, to: AST::Types::Bot.new)
          subs << type
          skips << type if skip
        end

        super_fvs = supers.each.with_object(Set.new) do |type, fvs|
          fvs.merge(type.free_variables)
        end
        sub_fvs = subs.each.with_object(Set.new) do |type, fvs|
          fvs.merge(type.free_variables)
        end

        unless super_fvs.disjoint?(unknowns) || sub_fvs.disjoint?(unknowns)
          raise UnsatisfiedInvariantError.new(
            reason: UnsatisfiedInvariantError::UnknownsFreeVariableNotDisjoint.new(
              var: var,
              lower_bound: sub_type,
              upper_bound: super_type
            ),
            constraints: self
          )
        end
      end

      def eliminate_variable(type, to:)
        case type
        when AST::Types::Name::Instance, AST::Types::Name::Alias, AST::Types::Name::Interface
          type.args.map do |ty|
            eliminate_variable(ty, to: AST::Types::Any.new)
          end.yield_self do |args|
            type.class.new(name: type.name, args: args, location: type.location)
          end
        when AST::Types::Union
          type.types.map do |ty|
            eliminate_variable(ty, to: AST::Types::Any.new)
          end.yield_self do |types|
            AST::Types::Union.build(types: types)
          end
        when AST::Types::Intersection
          type.types.map do |ty|
            eliminate_variable(ty, to: AST::Types::Any.new)
          end.yield_self do |types|
            AST::Types::Intersection.build(types: types)
          end
        when AST::Types::Var
          if vars.member?(type.name)
            to
          else
            type
          end
        else
          type
        end
      end

      def unknown?(var)
        dictionary.key?(var)
      end

      def unknowns
        Set.new(dictionary.keys)
      end

      def unknown!(var)
        unless unknown?(var)
          dictionary[var] = [Set.new, Set.new, Set.new]
        end
      end

      def empty?
        dictionary.keys.empty?
      end

      def upper_bound(var, skip: false)
        _, upper_bound, skips = dictionary[var]
        upper_bound -= skips if skip

        case upper_bound.size
        when 0
          AST::Types::Top.new
        when 1
          upper_bound.first
        else
          AST::Types::Intersection.build(types: upper_bound.to_a)
        end
      end

      def lower_bound(var, skip: false)
        lower_bound, _, skips = dictionary[var]
        lower_bound -= skips if skip

        case lower_bound.size
        when 0
          AST::Types::Bot.new
        when 1
          lower_bound.first
        else
          AST::Types::Union.build(types: lower_bound.to_a)
        end
      end

      Context = Struct.new(:variance, :self_type, :instance_type, :class_type, keyword_init: true)

      def solution(checker, variance: nil, variables:, self_type: nil, instance_type: nil, class_type: nil, context: nil)
        if context
          raise if variance
          raise if self_type
          raise if instance_type
          raise if class_type

          variance = context.variance
          self_type = context.self_type
          instance_type = context.instance_type
          class_type = context.class_type
        end

        vars = []
        types = []

        dictionary.each_key do |var|
          if variables.include?(var)
            if has_constraint?(var)
              relation = Relation.new(
                sub_type: lower_bound(var, skip: false),
                super_type: upper_bound(var, skip: false)
              )

              checker.check(relation, self_type: self_type, instance_type: instance_type, class_type: class_type, constraints: self.class.empty).yield_self do |result|
                if result.success?
                  vars << var

                  upper_bound = upper_bound(var, skip: true)
                  lower_bound = lower_bound(var, skip: true)

                  type =
                    case
                    when variance.contravariant?(var)
                      upper_bound
                    when variance.covariant?(var)
                      lower_bound
                    else
                      if lower_bound.level.join > upper_bound.level.join
                        upper_bound
                      else
                        lower_bound
                      end
                    end

                  types << type
                else
                  raise UnsatisfiableConstraint.new(
                    var: var,
                    sub_type: result.relation.sub_type,
                    super_type: result.relation.super_type,
                    result: result
                  )
                end
              end
            else
              vars << var
              types << AST::Types::Any.new
            end
          end
        end

        Interface::Substitution.build(vars, types)
      end

      def has_constraint?(var)
        lower, upper, skips = dictionary[var]
        lower -= skips
        upper -= skips
        !lower.empty? || !upper.empty?
      end

      def each
        if block_given?
          dictionary.each_key do |var|
            yield var, lower_bound(var), upper_bound(var)
          end
        else
          enum_for :each
        end
      end

      def to_s
        strings = each.map do |var, lower_bound, upper_bound|
          "#{lower_bound} <: #{var} <: #{upper_bound}"
        end

        "#{unknowns.to_a.join(",")}/#{vars.to_a.join(",")} |- { #{strings.join(", ")} }"
      end
    end
  end
end
