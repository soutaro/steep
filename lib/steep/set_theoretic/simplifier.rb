module Steep
  module SetTheoretic
    # Simplifies the types the narrowing builds, so that they read like the types a user writes.
    #
    # - `untyped & T` is `T` and `untyped & !T` is `untyped`: narrowing an `untyped` value is a static assertion
    # - An empty clause is dropped (`String & Integer`), and so is a clause another one subsumes (`Integer | Numeric`)
    # - A redundant atom is dropped: `Numeric & Integer` is `Integer`, and `Foo & !Taggable` is `Foo` when no class
    #   under `Foo` includes `Taggable` in the environment (the type only grows, so the evidence of the environment is enough)
    # - A negation is dropped when the union covers it: `Integer | (Numeric & !Integer)` is `Numeric`
    # - An alias is unfolded only when it interacts with the other atoms, so that `dm & !M1` keeps `ds` when `ds` has no `M1`
    class Simplifier
      attr_reader :emptiness

      attr_reader :normalizer

      def initialize(emptiness:)
        @emptiness = emptiness
        @normalizer = Normalizer.new(factory: emptiness.factory, expand_aliases: false)
      end

      def factory
        emptiness.factory
      end

      # The simplified `type`, or the first of `candidates` that is equivalent to it
      def simplify(type, bounds: {}, candidates: [])
        finish(simplify_clauses(normalizer.normalize(type).clauses, bounds), bounds, candidates)
      end

      # The simplified `type & predicate`
      #
      # Unlike `Intersection.build`, `untyped & predicate` is `predicate`.
      def intersect(type, predicate, bounds: {}, candidates: [])
        dnf = normalizer.normalize(type) & normalizer.normalize(predicate)
        finish(simplify_clauses(dnf.clauses, bounds), bounds, candidates)
      end

      # Returns the first of `candidates` that normalizes to the same clauses, so that the original type keeps its
      # spelling when the simplification changes nothing; the comparison is syntactic because `untyped` is consistent
      # with every type
      def finish(clauses, bounds, candidates)
        dnf = DNF.new(clauses)
        candidates.each do |candidate|
          return candidate if normalizer.normalize(candidate) == dnf
        end
        dnf.to_type
      end

      def simplify_clauses(clauses, bounds)
        result = [] #: Array[DNF::Clause]
        queue = clauses.dup

        until queue.empty?
          clause = untyped_rule(queue.shift || raise)
          next if clause.contradiction?
          next if emptiness.check(clause.to_type, mode: :inhabitation, bounds: bounds).empty?

          alias_type = clause.positives.find {|type| type.is_a?(AST::Types::Name::Alias) }
          if alias_type.is_a?(AST::Types::Name::Alias) && !(clause.positives.size == 1 && clause.negatives.empty?)
            rest = DNF::Clause.new(positives: clause.positives - [alias_type], negatives: clause.negatives)
            expanded = factory.expand_alias(alias_type)

            case
            when emptiness.subtype(rest.to_type, alias_type, bounds: bounds)
              # The alias is redundant
              queue.unshift(rest)
            when emptiness.subtype(alias_type, rest.to_type, bounds: bounds)
              # The other atoms are redundant
              result << DNF::Clause.new(positives: Set[alias_type], negatives: Set[])
            when expanded == alias_type
              result << simplify_clause(clause, bounds)
            else
              queue = (normalizer.normalize(expanded) & DNF.new([rest])).clauses + queue
            end

            next
          end

          result << simplify_clause(clause, bounds)
        end

        result = absorb(result, bounds)
        eliminate_against_union(result, bounds)
      end

      def untyped_rule(clause)
        any = AST::Types::Any.instance

        if clause.positives.include?(any)
          if clause.positives.size > 1
            DNF::Clause.new(positives: clause.positives - [any], negatives: clause.negatives)
          else
            DNF::Clause.new(positives: Set[any], negatives: Set[])
          end
        else
          clause
        end
      end

      def simplify_clause(clause, bounds)
        positives = clause.positives.to_a
        kept = [] #: Array[AST::Types::t]

        positives.each_with_index do |type, index|
          redundant = positives.each_with_index.any? do |other, other_index|
            next false if index == other_index
            next false unless emptiness.subtype(other, type, bounds: bounds)
            # Equivalent atoms: the first one stays
            !(other_index > index && emptiness.subtype(type, other, bounds: bounds))
          end

          kept << type unless redundant
        end

        negatives = clause.negatives.reject do |negative|
          emptiness.check(
            AST::Types::Intersection.build(types: kept + [negative]),
            mode: :subtyping,
            bounds: bounds
          ).empty_in_rbs_or_stronger?
        end

        DNF::Clause.new(positives: Set.new(kept), negatives: Set.new(negatives))
      end

      # Drops the clauses another clause subsumes
      def absorb(clauses, bounds)
        types = clauses.map(&:to_type)

        clauses.select.with_index do |_, index|
          type = types.fetch(index)
          !types.each_with_index.any? do |other, other_index|
            next false if index == other_index
            next false unless emptiness.subtype(type, other, bounds: bounds)
            !(other_index > index && emptiness.subtype(other, type, bounds: bounds))
          end
        end
      end

      # Drops the negations the union covers: `Integer | (Numeric & !Integer)` is `Integer | Numeric`
      def eliminate_against_union(clauses, bounds)
        union = DNF.new(clauses).to_type
        changed = false

        clauses = clauses.map do |clause|
          if clause.negatives.empty?
            clause
          else
            negatives = clause.negatives.to_a
            clause.negatives.each do |negative|
              candidate = DNF::Clause.new(positives: clause.positives, negatives: Set.new(negatives - [negative]))
              if emptiness.subtype(candidate.to_type, union, bounds: bounds)
                negatives.delete(negative)
                changed = true
              end
            end

            DNF::Clause.new(positives: clause.positives, negatives: Set.new(negatives))
          end
        end

        if changed
          absorb(clauses, bounds)
        else
          clauses
        end
      end
    end
  end
end
