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
        # `unconditional` carries the ivar refinement (set_x pattern) AND
        # the return-value establishment (build pattern). Either can be
        # present without the other — `build` establishes a return
        # attribute while setting no ivar — so the branch is assembled
        # from whatever slots the entry has, and emitted only if non-empty.
        unconditional = {}
        unless entry.ivars.empty?
          unconditional.merge!(serialize_branch(
            ivars: entry.ivars,
            self_type_string: entry.self_type_string
          ))
        end
        unless entry.returns_establishes.empty?
          unconditional["returns"] = {
            "establishes" => entry.returns_establishes.map(&:to_s).sort
          }
        end
        row["unconditional"] = unconditional unless unconditional.empty?
        # The MAY-write effect (felixefelip/steep#68): not a refinement, so it
        # sits outside the branches — it applies at every call site, and only
        # tells the caller to stop trusting its narrowing of these ivars.
        effects = {}
        effects["may_write"] = entry.may_write_ivars.map(&:to_s).sort unless entry.may_write_ivars.empty?
        # felixefelip/steep#68 item 2: halt-check getter link.
        effects["returns_ivar"] = entry.returns_ivar.to_s if entry.returns_ivar
        row["effects"] = effects unless effects.empty?

        # felixefelip/steep#68 item 2: self-methods proven non-nil on the
        # unhalted exit, keyed by the gate ivar.
        unless entry.conditional_returns.empty?
          row["conditional_returns"] = entry.conditional_returns.sort_by { |m, _| m.to_s }.each_with_object({}) do |(method, spec), acc|
            acc[method.to_s] = {
              "gate_ivar" => spec[:gate_ivar].to_s,
              "type" => spec[:type].to_s
            }
          end
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
