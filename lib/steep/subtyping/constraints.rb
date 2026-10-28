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

          def initialize(var:, lower_bound:, upper_bound:)
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

      # The method type relations whose domain has an unknown variable: the overload the arguments reach depends on
      # the variable, so that the relation is checked once the variable is solved
      attr_reader :deferred

      def initialize(unknowns:)
        @dictionary = {}
        @vars = Set.new
        @deferred = []
        @deferring = true

        unknowns.each do |var|
          dictionary[var] = [Set.new, Set.new, Set.new]
        end
      end

      # `false` while the deferred relations are checked with the variables left unknown
      def deferring?
        @deferring
      end

      def defer(name:, sub_method:, super_type:)
        deferred << [name, sub_method, super_type]
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
            constraints: self
          )
        end
      end

      def add(var, sub_type: nil, super_type: nil, skip: false)
        subs, supers, skips = dictionary.fetch(var)

        if sub_type.is_a?(AST::Types::Logic::Base)
          sub_type = AST::Builtin.bool_type
        end

        if super_type.is_a?(AST::Types::Logic::Base)
          super_type = AST::Builtin.bool_type
        end

        if super_type && !super_type.is_a?(AST::Types::Top)
          type = eliminate_variable(super_type, to: AST::Types::Top.instance)
          supers << type
          skips << type if skip
        end

        if sub_type && !sub_type.is_a?(AST::Types::Bot)
          type = eliminate_variable(sub_type, to: AST::Types::Bot.instance)
          subs << type
          skips << type if skip
        end

        super_fvs = supers.each_with_object(Set.new) do |type, fvs|
          fvs.merge(type.free_variables)
        end
        sub_fvs = subs.each_with_object(Set.new) do |type, fvs|
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
            eliminate_variable(ty, to: AST::Types::Any.instance)
          end.yield_self do |args|
            type.class.new(name: type.name, args: args)
          end
        when AST::Types::Union
          type.types.map do |ty|
            eliminate_variable(ty, to: AST::Types::Any.instance)
          end.yield_self do |types|
            AST::Types::Union.build(types: types)
          end
        when AST::Types::Intersection
          type.types.map do |ty|
            eliminate_variable(ty, to: AST::Types::Any.instance)
          end.yield_self do |types|
            AST::Types::Intersection.build(types: types)
          end
        when AST::Types::Var
          if vars.member?(type.name)
            to
          else
            type
          end
        when AST::Types::Tuple
          AST::Types::Tuple.new(
            types: type.types.map {|ty| eliminate_variable(ty, to: AST::Builtin.any_type) }
          )
        when AST::Types::Record
          type.map_type { eliminate_variable(_1, to: AST::Builtin.any_type) }
        when AST::Types::Proc
          type.map_type {|ty| eliminate_variable(ty, to: AST::Builtin.any_type) }
        when AST::Types::Negation
          type.map_type {|ty| eliminate_variable(ty, to: AST::Builtin.any_type) }
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
        if skip
          upper_bound = upper_bound_types(var)
        else
          _, upper_bound, _ = dictionary.fetch(var)
        end

        case upper_bound.size
        when 0
          AST::Types::Top.instance
        when 1
          upper_bound.first || raise
        else
          AST::Types::Intersection.build(types: upper_bound.to_a)
        end
      end

      def lower_bound(var, skip: false)
        lower_bound = lower_bound_types(var)

        case lower_bound.size
        when 0
          AST::Types::Bot.instance
        when 1
          lower_bound.first || raise
        else
          AST::Types::Union.build(types: lower_bound.to_a)
        end
      end

      Context = _ = Struct.new(:variance, :self_type, :instance_type, :class_type, keyword_init: true)

      # The solution of the variables, one variable at a time
      #
      # A variable is solved when its bounds, with the solved variables substituted, have no other variable to solve,
      # and when a deferred relation mentions it only if it has a bound: the variables of the domains of the deferred
      # relations are solved first, the relations are checked with them substituted, which bounds the variables of
      # their return types, and the other variables follow. When no variable is ready, the deferred relations are
      # checked with the variables left unknown, as the rules without deferral do, and the first variable is solved.
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

        remaining = dictionary.each_key.select {|var| variables.include?(var) }
        solved = {} #: Hash[Symbol, AST::Types::t]

        until remaining.empty?
          subst = Interface::Substitution.build(solved.keys, solved.values)
          check_deferred(checker, subst, remaining, force: false, self_type: self_type, instance_type: instance_type, class_type: class_type)

          var = remaining.find {|v| ready?(v, remaining, subst) }
          unless var
            subst = Interface::Substitution.build(solved.keys, solved.values)
            check_deferred(checker, subst, remaining, force: true, self_type: self_type, instance_type: instance_type, class_type: class_type)
            var = remaining.find {|v| ready?(v, remaining, subst) } || remaining.fetch(0)
          end

          subst = Interface::Substitution.build(solved.keys, solved.values)
          solved[var] = solve_variable(checker, var, subst, variance, self_type: self_type, instance_type: instance_type, class_type: class_type)
          remaining.delete(var)
        end

        subst = Interface::Substitution.build(solved.keys, solved.values)
        check_deferred(checker, subst, remaining, force: true, self_type: self_type, instance_type: instance_type, class_type: class_type)

        Interface::Substitution.build(solved.keys, solved.values)
      end

      # `true` if the bounds of the variable mention no variable left to solve, and a deferred relation mentions the
      # variable only if it has a bound
      def ready?(var, remaining, subst)
        others = remaining - [var]

        bounds = lower_bound_types(var).to_a + upper_bound_types(var).to_a
        return false if bounds.any? {|type| type.subst(subst).free_variables.any? {|fv| others.include?(fv) } }

        bounded?(var) || !deferred_mention?(var)
      end

      # `true` if a deferred relation mentions the variable
      def deferred_mention?(var)
        deferred.any? do |_, sub_method, super_type|
          super_type.free_variables.include?(var) || sub_method.method_types.any? {|type| type.free_variables.include?(var) }
        end
      end

      # Checks the deferred relations whose domains have no variable left to solve, with the solved variables
      # substituted; `force` checks every deferred relation, with the variables left unknown
      def check_deferred(checker, subst, remaining, force:, self_type:, instance_type:, class_type:)
        deferred.dup.each do |item|
          name, sub_method, super_type = item
          super_type = super_type.subst(subst)
          sub_method = Interface::Shape::Entry.new(
            overloads: sub_method.overloads.map {|overload| overload.subst(subst) },
            private_method: sub_method.private_method?,
            method_name: sub_method.method_name
          )

          open = Check.domain_free_variables(super_type).any? {|fv| fv.is_a?(Symbol) && unknown?(fv) }
          next if open && !force

          deferred.delete(item)

          super_method = Interface::Shape::Entry.new(
            overloads: [Interface::Shape::MethodOverload.new(super_type, [])],
            private_method: sub_method.private_method?,
            method_name: sub_method.method_name
          )
          relation = Relation.new(sub_type: sub_method, super_type: super_method)
          result =
            begin
              @deferring = false if open
              checker.with_context(self_type: self_type, instance_type: instance_type, class_type: class_type, constraints: self) do
                checker.check_method(name, relation)
              end
            ensure
              @deferring = true
            end

          if result.failure?
            domain_var = Check.domain_free_variables(super_type).find {|fv| fv.is_a?(Symbol) && unknown?(fv) }
            var = (domain_var if domain_var.is_a?(Symbol)) || remaining.first || dictionary.each_key.first or raise
            raise UnsatisfiableConstraint.new(
              var: var,
              sub_type: lower_bound(var).subst(subst),
              super_type: upper_bound(var).subst(subst),
              result: result
            )
          end
        end
      end

      def solve_variable(checker, var, subst, variance, self_type:, instance_type:, class_type:)
        return AST::Types::Any.instance unless bounded?(var)

        relation = Relation.new(
          sub_type: lower_bound(var, skip: false).subst(subst),
          super_type: upper_bound(var, skip: false).subst(subst)
        )

        result = checker.check(relation, self_type: self_type, instance_type: instance_type, class_type: class_type, constraints: self.class.empty)
        unless result.success?
          raise UnsatisfiableConstraint.new(
            var: var,
            sub_type: result.relation.sub_type,
            super_type: result.relation.super_type,
            result: result
          )
        end

        upper_bound = upper_bound(var, skip: true).subst(subst)
        lower_bound = lower_bound(var, skip: true).subst(subst)

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
      end

      # `true` if the variable has a bound, or is mentioned by a deferred relation, which bounds it once checked
      def has_constraint?(var)
        bounded?(var) || deferred_mention?(var)
      end

      # `true` if the variable has a lower or an upper bound
      def bounded?(var)
        !upper_bound_types(var).empty? || !lower_bound_types(var).empty?
      end

      def each
        if block_given?
          dictionary.each_key do |var|
            yield [var, lower_bound(var), upper_bound(var)]
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

      def lower_bound_types(var_name)
        lower, _, _ = dictionary.fetch(var_name)
        lower
      end

      def upper_bound_types(var_name)
        _, upper, skips = dictionary.fetch(var_name)

        case
        when upper.empty?
          skips
        when skips.empty?
          upper
        else
          upper - skips
        end
      end
    end
  end
end
