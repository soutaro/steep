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
        (cache[path] ||= self.class.index_for(path: path.to_s, max_index: max_index)) == index
      end

      alias === =~

      def self.index_for(path:, max_index:)
        Digest::MD5.hexdigest(path).hex % max_index
      end
    end
  end
end
