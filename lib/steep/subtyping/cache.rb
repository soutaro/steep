module Steep
  module Subtyping
    class Cache
      attr_reader :subtypes

      attr_reader :ground_subtypes

      def initialize
        @subtypes = {}
        @ground_subtypes = {}
        Stats.active&.register_cache(self)
      end

      def subtype(relation, self_type, instance_type, class_type, bounds)
        key = [relation, self_type, instance_type, class_type, bounds] #: context_key
        subtypes[key]
      end

      def [](relation, self_type, instance_type, class_type, bounds)
        key = [relation, self_type, instance_type, class_type, bounds] #: context_key
        subtypes[key]
      end

      def []=(relation, self_type, instance_type, class_type, bounds, value)
        key = [relation, self_type, instance_type, class_type, bounds] #: context_key
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
