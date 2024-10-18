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

      def =~(target_path)
        key = stringify(target_path)
        (cache[key] ||= self.class.index_for(key: key, max_index: max_index)) == index
      end

      alias === =~

      def assign!(path, index)
        key = stringify(path)
        cache[key] = index
        self
      end

      def stringify(target_path)
        target =
          case target_path[0]
          when Project::Target
            target_path[0].name.to_s
          else
            target_path[0].to_s
          end
        path = target_path[1].to_s
        "#{target}::#{path}"
      end

      def self.index_for(key:, max_index:)
        Digest::MD5.hexdigest(key).hex % max_index
      end
    end
  end
end
