module Steep
  module Postconditions
    # Serializes `InferredEntry` instances to the `.steep_postconditions.yml`
    # schema consumed by `Postconditions::Store.from_hash`. The output is
    # round-trip-compatible with hand-written sidecars: a Steep-generated
    # entry and a rbs_rails-generated entry sit side-by-side in `sig/**/`
    # and are merged by the loader.
    class Writer
      def self.dump(entries)
        new(entries).dump
      end

      def self.write(path, entries)
        new(entries).write(path)
      end

      def initialize(entries)
        @entries = entries
      end

      def dump
        YAML.dump(payload)
      end

      def write(path)
        path = Pathname(path) unless path.is_a?(Pathname)
        path.parent.mkpath
        path.write(dump)
      end

      private

      def payload
        rows = @entries
          .sort_by { |entry| sort_key(entry) }
          .map { |entry| serialize_entry(entry) }

        {
          "version" => 1,
          "postconditions" => rows
        }
      end

      def sort_key(entry)
        [entry.class_name, entry.singleton ? 1 : 0, entry.method_name.to_s]
      end

      def serialize_entry(entry)
        row = {
          "class" => entry.class_name,
          "method" => entry.method_name.to_s
        }
        unless entry.ivars.empty?
          row["unconditional"] = serialize_branch(
            ivars: entry.ivars,
            self_type_string: entry.self_type_string
          )
        end
        unless entry.when_true_ivars.empty?
          row["when_true"] = serialize_branch(
            ivars: entry.when_true_ivars,
            self_type_string: entry.when_true_self_type_string
          )
        end
        row
      end

      def serialize_branch(ivars:, self_type_string:)
        branch = {
          "ivars" => ivars.sort_by { |k, _| k.to_s }.each_with_object({}) do |(name, type), hash|
            hash[name.to_s] = type.to_s
          end
        }
        if self_type_string.is_a?(String) && !self_type_string.empty?
          branch["self"] = self_type_string
        end
        branch
      end
    end
  end
end
