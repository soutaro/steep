module Steep
  # Generic callback sidecar (issue felixefelip/steep#27).
  #
  # Loads `.steep_callbacks.yml`, a sidecar produced by external generators
  # (rbs_rails for Rails `before_action`, hand-authored, any framework that
  # has a "method H runs before method M" lifecycle) that lets Steep apply
  # `H`'s `unconditional` postcondition to the env at the entry of `M`,
  # **as if** `H` had been called explicitly inside `M`'s body.
  #
  # The mechanism is framework-agnostic: Steep does not know about
  # `before_action`, `before_save`, Hanami `before`, or Sidekiq middleware.
  # It only knows "if you say H runs before M, I'll apply H's unconditional
  # postcondition to M's initial env."
  #
  # Schema:
  #
  #     ---
  #     version: 1
  #     callbacks:
  #       # handler style (controller before_action): apply the handler's
  #       # unconditional postcondition ivar refinements at method entry.
  #       - class: PostsController
  #         apply_postcondition_of: set_post
  #         runs_before: [show, edit, update, destroy, publish]
  #       # self style (ActiveRecord after-validation callback): refine `self`
  #       # directly at method entry, because the record is known to satisfy
  #       # its validations once the callback runs.
  #       - class: Dose
  #         applies_self: "Dose & Dose::Validated"
  #         runs_before: [atualizar_calendario]
  #
  # Semantics: for each entry, at the entry of every method in `runs_before`
  # on the matching class, Steep applies the entry's narrowing to the initial
  # env:
  #   - `apply_postcondition_of` looks up the handler's `unconditional`
  #     postcondition (from the `.steep_postconditions.yml` machinery, issue
  #     felixefelip/steep#23) and refines `instance_variable_types`. If the
  #     handler has no `unconditional` postcondition, that part is ignored.
  #   - `applies_self` refines the method's `self` type to the given RBS type.
  # An entry may carry either or both.
  module Callbacks
    DEFAULT_SIDECAR_GLOB = "sig/**/.steep_callbacks.yml".freeze

    class << self
      def load(base_dir, glob: DEFAULT_SIDECAR_GLOB)
        paths = Dir.glob(File.join(base_dir.to_s, glob)).sort
        return Store.empty if paths.empty?

        merged = {} #: Hash[String, Array[Entry]]
        sources = []

        paths.each do |path|
          absolute = Pathname.new(path)
          raw = YAML.safe_load(absolute.read, aliases: true)
          next unless raw

          sub = Store.from_hash(raw, source: absolute.to_s)
          sub.entries_by_class.each do |class_name, entries|
            merged[class_name] ||= []
            merged[class_name].concat(entries)
          end
          sources << absolute.to_s
        rescue Psych::Exception, LoadError => e
          Steep.logger.warn { "[callbacks] failed to parse #{absolute}: #{e.message}" }
        end

        Store.new(entries_by_class: merged, source: sources.join(", "))
      end
    end

    class Store
      attr_reader :entries_by_class, :source

      def self.empty
        new(entries_by_class: {}, source: nil)
      end

      def self.from_hash(raw, source:)
        rows = (raw && raw["callbacks"]) || []
        grouped = {} #: Hash[String, Array[Entry]]
        rows.each do |row|
          entry = Entry.parse(row, source: source)
          next unless entry
          grouped[entry.class_name] ||= []
          grouped[entry.class_name] << entry
        end
        new(entries_by_class: grouped, source: source)
      end

      def initialize(entries_by_class:, source:)
        @entries_by_class = entries_by_class
        @source = source
      end

      def empty?
        @entries_by_class.empty?
      end

      # Returns all callback entries whose `runs_before` includes
      # `method_name` for the given class. Order of returned entries
      # mirrors declaration order — relevant for last-wins composition
      # when two handlers write the same ivar.
      def lookup_callbacks_for_method(type_name, method_name)
        key = type_name.to_s.sub(/\A::/, "")
        method_sym = method_name.to_sym
        entries = @entries_by_class[key]
        return [] unless entries

        entries.select { |entry| entry.runs_before.include?(method_sym) }
      end
    end

    class Entry
      attr_reader :class_name, :handler_method, :applies_self, :runs_before, :singleton, :source

      def self.parse(row, source:)
        return nil unless row.is_a?(Hash)

        klass = row["class"]
        handler = row["apply_postcondition_of"]
        applies_self = row["applies_self"]
        runs_before = row["runs_before"]
        singleton = row["singleton"] == true

        return nil unless klass.is_a?(String) && !klass.empty?

        # An entry narrows in one of two ways:
        #   - apply_postcondition_of: <handler> — apply the handler's
        #     `unconditional` postcondition ivar refinements (controller
        #     before_action style).
        #   - applies_self: <RBS type> — refine `self` directly at method
        #     entry (ActiveRecord after-validation callback style, where the
        #     record is known to satisfy its validations, e.g.
        #     `Dose & Dose::Validated`).
        # At least one must be present.
        has_handler = handler.is_a?(String) && !handler.empty?
        has_self = applies_self.is_a?(String) && !applies_self.empty?
        return nil unless has_handler || has_self

        return nil unless runs_before.is_a?(Array) && runs_before.any?

        method_syms = runs_before.filter_map do |name|
          case name
          when String then name.to_sym unless name.empty?
          when Symbol then name
          else
            Steep.logger.warn { "[callbacks] runs_before entry must be a string/symbol, got #{name.inspect} in #{source}" }
            nil
          end
        end
        return nil if method_syms.empty?

        new(
          class_name: klass,
          handler_method: has_handler ? handler.to_sym : nil,
          applies_self: has_self ? applies_self : nil,
          runs_before: method_syms,
          singleton: singleton,
          source: source
        )
      end

      def initialize(class_name:, handler_method: nil, applies_self: nil, runs_before:, singleton: false, source: nil)
        @class_name = class_name
        @handler_method = handler_method
        @applies_self = applies_self
        @runs_before = runs_before
        @singleton = singleton
        @source = source
      end
    end
  end
end
