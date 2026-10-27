module Steep
  module SetTheoretic
    # The disjunctive normal form of a type: a union of clauses, each the intersection of atoms and negated atoms.
    #
    # An atom is a type that is not a union, an intersection, a negation, an alias, `bool`, `top`, or `bot`:
    # class instances, singletons, literals, `nil`, `untyped`, type variables, tuples, records, procs, and interfaces.
    class DNF
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

      def bot?
        clauses.empty?
      end

      def top?
        clauses.any?(&:top?)
      end

      def |(other)
        DNF.new((clauses + other.clauses).uniq)
      end

      def &(other)
        DNF.new(
          clauses.product(other.clauses).map {|c1, c2| c1 & c2 }.reject(&:contradiction?).uniq
        )
      end

      # De Morgan: `!(C1 | C2)` is `!C1 & !C2`, and `!(p1 & p2 & !n1)` is `!p1 | !p2 | n1`
      def negate
        clauses.inject(DNF.top) do |dnf, clause|
          negated = DNF.bot
          clause.positives.each do |type|
            negated |= DNF.new([Clause.new(positives: Set[], negatives: Set[type])])
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
    class Normalizer
      attr_reader :factory

      def initialize(factory:)
        @factory = factory
      end

      def normalize(type, expanding = Set[])
        case type
        when AST::Types::Top, AST::Types::Void
          DNF.top
        when AST::Types::Bot
          DNF.bot
        when AST::Types::Union
          type.types.inject(DNF.bot) {|dnf, ty| dnf | normalize(ty, expanding) }
        when AST::Types::Intersection
          type.types.inject(DNF.top) {|dnf, ty| dnf & normalize(ty, expanding) }
        when AST::Types::Negation
          normalize(type.type, expanding).negate
        when AST::Types::Boolean, AST::Types::Logic::Base
          DNF.atom(AST::Types::Literal.new(value: true)) | DNF.atom(AST::Types::Literal.new(value: false))
        when AST::Types::Name::Alias
          if expanding.include?(type.name)
            # A cycle at the top level of the alias, which RBS rejects; keep it opaque
            DNF.atom(type)
          else
            expanded = factory.expand_alias(type)
            if expanded == type
              DNF.atom(type)
            else
              normalize(expanded, expanding + [type.name])
            end
          end
        when AST::Types::Name::Instance
          case
          when AST::Builtin::NilClass.instance_type?(type)
            DNF.atom(AST::Types::Nil.instance)
          when AST::Builtin::TrueClass.instance_type?(type)
            DNF.atom(AST::Types::Literal.new(value: true))
          when AST::Builtin::FalseClass.instance_type?(type)
            DNF.atom(AST::Types::Literal.new(value: false))
          else
            DNF.atom(type)
          end
        else
          DNF.atom(type)
        end
      end
    end
  end
end
