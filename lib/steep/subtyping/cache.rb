module Steep
  module Subtyping
    class Cache
      attr_reader :subtypes

      def initialize
        @subtypes = {}
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

      def no_subtype_cache?
        @subtypes.empty?
      end
    end
  end
end
