module Steep
  module Subtyping
    class Cache
      # Cache results are partitioned by the context (self/instance/class types),
      # which changes far less frequently than the relations being checked.
      #
      # `Check#with_context` fetches the bucket for the current context once, and
      # each `check_type` looks up the relation in that bucket, so the hot lookup
      # hashes a `Relation` (with a memoized hash) instead of building and
      # hashing a 5-element key array every time.
      class ContextBucket
        # Results for relations without variable upper bounds, keyed by the relation
        attr_reader :unbounded

        # Results for relations with variable upper bounds, keyed by `[relation, bounds]`
        attr_reader :bounded

        def initialize
          @unbounded = {}
          @bounded = {}
        end

        def [](relation, bounds)
          if bounds.empty?
            unbounded[relation]
          else
            bounded[[relation, bounds]]
          end
        end

        def []=(relation, bounds, value)
          if bounds.empty?
            unbounded[relation] = value
          else
            bounded[[relation, bounds]] = value
          end
        end

        def empty?
          unbounded.empty? && bounded.empty?
        end
      end

      def initialize
        @contexts = {}
      end

      def bucket(self_type, instance_type, class_type)
        @contexts[[self_type, instance_type, class_type]] ||= ContextBucket.new()
      end

      # Returns the cache contents keyed by `[relation, self_type, instance_type, class_type, bounds]`
      def subtypes
        hash = {} #: Hash[[Relation[AST::Types::t], AST::Types::t?, AST::Types::t?, AST::Types::t?, Hash[Symbol, AST::Types::t]], Result::t]

        @contexts.each do |(self_type, instance_type, class_type), bucket|
          bucket.unbounded.each do |relation, result|
            hash[[relation, self_type, instance_type, class_type, {}]] = result
          end
          bucket.bounded.each do |(relation, bounds), result|
            hash[[relation, self_type, instance_type, class_type, bounds]] = result
          end
        end

        hash
      end

      def no_subtype_cache?
        @contexts.all? {|_, bucket| bucket.empty? }
      end
    end
  end
end
