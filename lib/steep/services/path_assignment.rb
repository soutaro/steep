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
        self.class.stringify(target_path)
      end

      def self.stringify(target_path)
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

      # Distributes the given target-paths over `max_index` workers, balancing the total
      # file size assigned to each worker (Longest Processing Time greedy: largest files first
      # go to the least-loaded worker).
      #
      # Returns a PathAssignment whose cache maps every path to its assigned worker index,
      # so `assignment =~ target_path` reflects the balanced distribution instead of the MD5 hash.
      #
      def self.by_size(target_paths, index:, max_index:)
        entries = target_paths.map do |target_path|
          [stringify(target_path), file_weight(target_path[1])] #: [String, Integer]
        end
        entries.sort_by! {|entry| [-entry[1], entry[0]] }

        loads = Array.new(max_index, 0)
        assignment = new(index: index, max_index: max_index)

        entries.each do |entry|
          key = entry[0]
          weight = entry[1]
          i = min_load_index(loads)
          assignment.cache[key] = i
          loads[i] = loads.fetch(i) + weight
        end

        assignment
      end

      def self.min_load_index(loads)
        min_index = 0
        min = loads[0] || 0
        loads.each_with_index do |load, i|
          if load < min
            min = load
            min_index = i
          end
        end
        min_index
      end

      def self.file_weight(path)
        # +1 base weight so empty/missing files still count as work and ordering stays stable
        1 + (path.file? ? path.size : 0)
      rescue SystemCallError
        1
      end
    end
  end
end
