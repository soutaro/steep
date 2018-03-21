module Steep
  module Subtyping
    class Constraints
      class RecursiveConstraintError < StandardError
        attr_reader :var
        attr_reader :type

        def initialize(var:, type:)
          @var = var
          @type = type

          super "Constraint cannot be recursive: #{var}, #{type}"
        end
      end

      class UnsatisfiableConstraint < StandardError
        attr_reader :var
        attr_reader :sub_type
        attr_reader :super_type

        def initialize(var:, sub_type:, super_type:, result:)
          @var = var
          @sub_type = sub_type
          @super_type = super_type
          @result = result

          super "Unsatisfiable constraint on #{var}: #{sub_type} <: #{super_type}"
        end
      end

      attr_reader :dictionary

      def initialize(domain:)
        @dictionary = {}

        domain.each do |var|
          dictionary[var] = [[], []]
        end
      end

      def self.empty
        new(domain: [])
      end

      def add(var, sub_type: nil, super_type: nil)
        subs, supers = dictionary[var]

        supers << super_type if super_type
        subs << sub_type if sub_type
      end

      def domain?(var)
        dictionary.key?(var)
      end

      def empty?
        dictionary.keys.empty?
      end

      def upper_bound(var)
        dictionary[var].last.dup
      end

      def lower_bound(var)
        dictionary[var].first.dup
      end

      def subst(checker)
        s = Interface::Substitution.empty

        each_constraint do |var, subs, supers|
          case
          when subs.empty? && supers.empty?
            # skip
          when subs.empty?
            upper_bound = (supers.size > 1 ? AST::Types::Union.new(types: supers) : supers.first).subst(s)
            s.add!(var, upper_bound)
          when supers.empty?
            lower_bound = (subs.size > 1 ? AST::Types::Intersection.new(types: subs) : subs.first).subst(s)
            s.add!(var, lower_bound)
          else
            lower_bound = (subs.size > 1 ? AST::Types::Intersection.new(types: subs) : subs.first).subst(s)
            upper_bound = (supers.size > 1 ? AST::Types::Union.new(types: supers) : supers.first).subst(s)
            relation = Relation.new(sub_type: lower_bound, super_type: upper_bound)

            result = checker.check(relation, constraints: self.class.empty)
            if result.success?
              s.add!(var, lower_bound)
            else
              raise UnsatisfiableConstraint.new(var: var,
                                                sub_type: lower_bound,
                                                super_type: upper_bound,
                                                result: result)
            end
          end
        end

        s
      end

      def each_constraint
        if block_given?
          dictionary.each do |var, (subs, supers)|
            yield var, subs, supers
          end
        else
          enum_for :each_constraint
        end
      end

      def to_s
        strings = []

        each_constraint do |var, subs, supers|
          s = [subs.size > 0 && AST::Types::Intersection.new(types: subs),
               var,
               supers.size > 0 && AST::Types::Union.new(types: supers)].select(&:itself)
          strings << s.join("<:")
        end

        "{ #{strings.join(", ")} }"
      end
    end
  end
end
