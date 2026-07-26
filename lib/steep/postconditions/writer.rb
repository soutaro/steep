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

      def self.write(path, entries, method_entry_facts: {}, argument_entry_facts: {})
        new(entries, method_entry_facts: method_entry_facts, argument_entry_facts: argument_entry_facts).write(path)
      end

      def initialize(entries, method_entry_facts: {}, argument_entry_facts: {})
        @entries = entries
        @method_entry_facts = method_entry_facts
        @argument_entry_facts = argument_entry_facts
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

        document = {
          "version" => 1,
          "postconditions" => rows
        }
        document["method_entry_facts"] = method_entry_rows unless @method_entry_facts.empty?
        document["argument_entry_facts"] = argument_entry_rows unless @argument_entry_facts.empty?
        document
      end

      # Argument-sensitive entry facts (peça 3): facts holding at a method's entry only for
      # the callers that passed a specific literal at a given parameter.
      #
      #   argument_entry_facts:
      #   - class: Example7::Dispatcher
      #     method: show
      #     param: which
      #     pattern: ":name"
      #     consts: { Example7::Foo.name: "::String" }
      def argument_entry_rows
        rows = [] #: Array[Hash[String, untyped]]
        @argument_entry_facts.sort.each do |key, partitions|
          class_name, method_name = key.split("#", 2)
          partitions
            .sort_by { |p| [p[:param].to_s, p[:pattern]] }
            .each do |partition|
              rows << {
                "class" => class_name,
                "method" => method_name,
                "param" => partition[:param].to_s,
                "pattern" => partition[:pattern],
                "consts" => partition[:consts].sort.to_h
              }
            end
        end
        rows
      end

      # felixefelip/steep#68 item 4: facts holding at each method's entry.
      #
      #   method_entry_facts:
      #   - class: C
      #     method: log_it
      #     self_methods: { current_user: "::User" }
      #     consts: { Current.user: "::User" }
      def method_entry_rows
        @method_entry_facts.sort.map do |key, facts|
          class_name, method_name = key.split("#", 2)
          row = { "class" => class_name, "method" => method_name }
          row["self_methods"] = facts[:self_methods].sort.to_h { |m, t| [m.to_s, t] } unless facts[:self_methods].empty?
          row["consts"] = facts[:consts].sort.to_h unless facts[:consts].empty?
          row
        end
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
        # felixefelip/rbs_infer#71 (piece 1): sibling const attributes this setter
        # proves non-nil at a `Const.attr =` write site. The Runner has already
        # gated these on a delegating singleton, so serialize whatever survives.
        unless entry.establishes_consts.empty?
          unconditional["establishes_consts"] = entry.establishes_consts
            .sort_by { |name, _| name.to_s }
            .each_with_object({}) { |(name, type), h| h[name.to_s] = type.to_s }
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
        # felixefelip/steep#68 item 3: constant attributes proven non-nil on the
        # unhalted exit, keyed by the `Const.attr` path.
        unless entry.conditional_const_returns.empty?
          row["conditional_const_returns"] = entry.conditional_const_returns.sort.each_with_object({}) do |(path, spec), acc|
            acc[path] = {
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
