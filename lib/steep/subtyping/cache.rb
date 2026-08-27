module Steep
  module Subtyping
    class Cache
      # Results of relations that have free variables, keyed by the relation and the
      # context the check ran in
      attr_reader :subtypes

      # Results of relations without free variables, keyed by the relation alone
      #
      # The `self`/`instance`/`class` types count as free variables, so the result of
      # such a relation doesn't depend on the context of the check.
      #
      attr_reader :ground_subtypes

      def initialize
        @subtypes = {}
        @ground_subtypes = {}
        Stats.active&.register_cache(self)
      end

      def subtype(relation, self_type, instance_type, class_type, bounds)
        key = [relation, self_type, instance_type, class_type, bounds]
        subtypes[key]
      end

      def [](relation, self_type, instance_type, class_type, bounds)
        key = [relation, self_type, instance_type, class_type, bounds]
        subtypes[key]
      end

      def []=(relation, self_type, instance_type, class_type, bounds, value)
        key = [relation, self_type, instance_type, class_type, bounds]
        subtypes[key] = value
      end

      def ground(relation)
        ground_subtypes[relation]
      end

      def store_ground(relation, value)
        ground_subtypes[relation] = value
      end

      def no_subtype_cache?
        @subtypes.empty? && @ground_subtypes.empty?
      end
    end
  end
end
