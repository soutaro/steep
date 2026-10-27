module Steep
  module SetTheoretic
    # The disjunctive normal form of a type: a union of clauses, each the intersection of atoms and negated atoms.
    #
    # An atom is a type that is not a union, an intersection, a negation, an alias, `bool`, `top`, or `bot`:
    # class instances, singletons, literals, `nil`, `untyped`, type variables, tuples, records, procs, and interfaces.
    #
    # A clause another clause subsumes syntactically is dropped (`A | (A & B)` is `A`), and a product that would
    # exceed `MAX_CLAUSES` raises `TooLarge`, which the callers read as "unknown".
    class DNF
      # The bound on the number of clauses of a product
      MAX_CLAUSES = 4096 #: Integer

      # Raised when the DNF of a type has too many clauses to build
      class TooLarge < StandardError
      end

      class Clause
        attr_reader :positives, :negatives

        def initialize(positives:, negatives:)
          @positives = positives
          @negatives = negatives
        end

        def self.top
          new(positives: Set[], negatives: Set[])
        end

        def &(other)
          Clause.new(positives: positives + other.positives, negatives: negatives + other.negatives)
        end

        # `true` if an atom is both required and excluded, so that the clause is `bot` syntactically
        def contradiction?
          positives.intersect?(negatives)
        end

        def top?
          positives.empty? && negatives.empty?
        end

        def size
          positives.size + negatives.size
        end

        # `true` if every value of `other` is a value of this clause syntactically: the atoms of this clause are
        # among the atoms of `other`
        def subsumes?(other)
          positives.subset?(other.positives) && negatives.subset?(other.negatives)
        end

        def ==(other)
          other.is_a?(Clause) && other.positives == positives && other.negatives == negatives
        end

        alias eql? ==

        def hash
          self.class.hash ^ positives.hash ^ negatives.hash
        end

        def to_type
          types = positives.to_a + negatives.map {|type| AST::Types::Negation.build(type: type) }
          AST::Types::Intersection.build(types: types)
        end

        def to_s
          to_type.to_s
        end
      end

      attr_reader :clauses

      def initialize(clauses)
        @clauses = clauses
      end

      def self.bot
        new([])
      end

      def self.top
        new([Clause.top])
      end

      def self.atom(type)
        new([Clause.new(positives: Set[type], negatives: Set[])])
      end

      def self.negated_atom(type)
        new([Clause.new(positives: Set[], negatives: Set[type])])
      end

      # The clauses without the duplicates, the contradictions, and the ones another clause subsumes, in their order
      def self.prune(clauses)
        clauses = clauses.reject(&:contradiction?).uniq
        return clauses if clauses.size <= 1

        # A clause is subsumed by a smaller one only, so that a union of atoms costs nothing
        by_size = clauses.group_by(&:size)
        sizes = by_size.keys.sort
        return clauses if sizes.size == 1

        clauses.reject do |clause|
          sizes.any? do |size|
            size < clause.size && by_size.fetch(size).any? {|other| other.subsumes?(clause) }
          end
        end
      end

      def bot?
        clauses.empty?
      end

      def top?
        clauses.any?(&:top?)
      end

      def |(other)
        DNF.new(DNF.prune(clauses + other.clauses))
      end

      def &(other)
        if clauses.size * other.clauses.size > MAX_CLAUSES
          raise TooLarge, "The product of #{clauses.size} and #{other.clauses.size} clauses exceeds #{MAX_CLAUSES}"
        end

        DNF.new(
          DNF.prune(clauses.product(other.clauses).map {|c1, c2| c1 & c2 })
        )
      end

      # De Morgan: `!(C1 | C2)` is `!C1 & !C2`, and `!(p1 & p2 & !n1)` is `!p1 | !p2 | n1`
      def negate
        clauses.inject(DNF.top) do |dnf, clause|
          negated = DNF.bot
          clause.positives.each do |type|
            negated |= DNF.negated_atom(type)
          end
          clause.negatives.each do |type|
            negated |= DNF.atom(type)
          end
          dnf & negated
        end
      end

      def to_type
        AST::Types::Union.build(types: clauses.map(&:to_type))
      end

      def to_s
        to_type.to_s
      end

      def ==(other)
        other.is_a?(DNF) && Set.new(other.clauses) == Set.new(clauses)
      end

      alias eql? ==

      def hash
        self.class.hash ^ Set.new(clauses).hash
      end
    end

    # Builds the DNF of a type.
    #
    # Unions, intersections, and negations are expanded, aliases are unfolded at the top level, `bool` becomes
    # `true | false`, `void` becomes `top`, and the instance types of `NilClass`, `TrueClass`, and `FalseClass` become
    # `nil`, `true`, and `false`. Everything else is an atom.
    #
    # A negation is pushed down to the atoms before the connectives are expanded (`!(A & B)` is read as `!A | !B`),
    # so that the DNF of the negated type is never built only to be negated again.
    class Normalizer
      attr_reader :factory

      # `false` keeps the aliases as atoms
      attr_reader :expand_aliases

      def initialize(factory:, expand_aliases: true)
        @factory = factory
        @expand_aliases = expand_aliases
        @cache = {}
      end

      # The DNFs are immutable, so that the normalization of a type is computed once
      def normalize(type, expanding = Set[], negated = false)
        if expanding.empty?
          @cache[[type, negated]] ||= normalize0(type, expanding, negated)
        else
          normalize0(type, expanding, negated)
        end
      end

      def normalize0(type, expanding, negated)
        case type
        when AST::Types::Top, AST::Types::Void
          negated ? DNF.bot : DNF.top
        when AST::Types::Bot
          negated ? DNF.top : DNF.bot
        when AST::Types::Union
          if negated
            type.types.inject(DNF.top) {|dnf, ty| dnf & normalize(ty, expanding, true) }
          else
            DNF.new(DNF.prune(type.types.flat_map {|ty| normalize(ty, expanding, false).clauses }))
          end
        when AST::Types::Intersection
          if negated
            DNF.new(DNF.prune(type.types.flat_map {|ty| normalize(ty, expanding, true).clauses }))
          else
            type.types.inject(DNF.top) {|dnf, ty| dnf & normalize(ty, expanding, false) }
          end
        when AST::Types::Negation
          normalize(type.type, expanding, !negated)
        when AST::Types::Boolean, AST::Types::Logic::Base
          true_type = AST::Types::Literal.new(value: true)
          false_type = AST::Types::Literal.new(value: false)
          if negated
            DNF.negated_atom(true_type) & DNF.negated_atom(false_type)
          else
            DNF.atom(true_type) | DNF.atom(false_type)
          end
        when AST::Types::Name::Alias
          if !expand_aliases || expanding.include?(type.name)
            # A cycle at the top level of the alias, which RBS rejects; keep it opaque
            atom(type, negated)
          else
            expanded = factory.expand_alias(type)
            if expanded == type
              atom(type, negated)
            else
              normalize0(expanded, expanding + [type.name], negated)
            end
          end
        when AST::Types::Name::Instance
          case
          when AST::Builtin::NilClass.instance_type?(type)
            atom(AST::Types::Nil.instance, negated)
          when AST::Builtin::TrueClass.instance_type?(type)
            atom(AST::Types::Literal.new(value: true), negated)
          when AST::Builtin::FalseClass.instance_type?(type)
            atom(AST::Types::Literal.new(value: false), negated)
          else
            atom(type, negated)
          end
        else
          atom(type, negated)
        end
      end

      def atom(type, negated)
        negated ? DNF.negated_atom(type) : DNF.atom(type)
      end
    end
  end
end
