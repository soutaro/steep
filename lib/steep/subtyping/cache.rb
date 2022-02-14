module Steep
  module Subtyping
    class Cache
      attr_reader :subtypes

      def initialize
        @subtypes = {}
      end

      def subtype(relation, self_type, instance_type, class_type)
        key = [relation, self_type, instance_type, class_type]
        subtypes[key]
      end

      def [](relation, self_type, instance_type, class_type)
        key = [relation, self_type, instance_type, class_type]
        subtypes[key]
      end

      def []=(relation, self_type, instance_type, class_type, value)
        key = [relation, self_type, instance_type, class_type]
        subtypes[key] = value
      end

      def no_subtype_cache?
        @subtypes.empty?
      end
    end
  end
end
