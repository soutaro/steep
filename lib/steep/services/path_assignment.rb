module Steep
  module Services
    class PathAssignment
      attr_reader :index, :max_index, :cache

      def initialize(index:, max_index:)
        @index = index
        @max_index = max_index
        @cache = {}
      end

      def self.all
        new(index: 0, max_index: 1)
      end

      def =~(path)
        path = path.to_s

        if cache.key?(path)
          cache[path]
        else
          value = Digest::MD5.hexdigest(path).hex % max_index == index
          cache[path] = value
          value
        end
      end
    end
  end
end
