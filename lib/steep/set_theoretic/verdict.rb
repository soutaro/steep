module Steep
  module SetTheoretic
    # The result of an emptiness check of a type.
    #
    # - `empty`: the type has no value, whatever happens at runtime (`Integer & String`, `Integer & !Integer`)
    # - `empty_in_rbs`: the type has no value as long as the class hierarchy is exactly what the RBS environment declares
    #   (`Foo & Taggable` when no class in the environment includes `Taggable` under `Foo`); a runtime `include`,
    #   `extend`, or reopened class could still make it inhabited
    # - `inhabited`: there is no evidence that the type is empty
    #
    # Subtyping only trusts `empty`. Narrowing uses all three: an `empty` branch is unreachable, an `empty_in_rbs` branch
    # is type checked as reachable and reported with a weaker diagnostic.
    class Verdict
      KINDS = [:empty, :empty_in_rbs, :inhabited].freeze #: Array[kind]

      STRENGTH = { empty: 2, empty_in_rbs: 1, inhabited: 0 }.freeze #: Hash[kind, Integer]

      attr_reader :kind

      # Why the type is (possibly) empty; `nil` when it is inhabited
      attr_reader :reason

      def initialize(kind, reason = nil)
        KINDS.include?(kind) or raise ArgumentError, "Unknown verdict kind: #{kind.inspect}"
        @kind = kind
        @reason = reason
      end

      def self.empty(reason = nil)
        new(:empty, reason)
      end

      def self.empty_in_rbs(reason = nil)
        new(:empty_in_rbs, reason)
      end

      INHABITED = new(:inhabited) #: Verdict

      def self.inhabited
        INHABITED
      end

      def empty?
        kind == :empty
      end

      def empty_in_rbs?
        kind == :empty_in_rbs
      end

      def inhabited?
        kind == :inhabited
      end

      # `true` if the type is empty under the assumption that the RBS environment declares the whole class hierarchy
      def empty_in_rbs_or_stronger?
        !inhabited?
      end

      def strength
        STRENGTH.fetch(kind)
      end

      # The verdict of an intersection, given the verdicts of its parts: one empty part makes it empty, so the strongest
      # evidence wins.
      def &(other)
        case
        when strength > other.strength
          self
        when strength < other.strength
          other
        else
          reason ? self : other
        end
      end

      # The verdict of a union, given the verdicts of its parts: every part must be empty, so the weakest evidence wins.
      def |(other)
        case
        when strength < other.strength
          self
        when strength > other.strength
          other
        else
          reason ? self : other
        end
      end

      def ==(other)
        other.is_a?(Verdict) && other.kind == kind && other.reason == reason
      end

      alias eql? ==

      def hash
        self.class.hash ^ kind.hash ^ reason.hash
      end

      def to_s
        if reason
          "#{kind} (#{reason})"
        else
          kind.to_s
        end
      end

      alias inspect to_s
    end
  end
end
