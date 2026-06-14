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
  #       # constant style (global state populated by an earlier callback,
  #       # e.g. CurrentAttributes): refine how constant reads are typed
  #       # inside the listed methods.
  #       - class: PostsController
  #         applies_constants:
  #           Current: "singleton(Current) & Current::UserPopulated"
  #         runs_before: [index, show]
  #       # top-level style: apply the narrowing to a class's top-level body
  #       # (a file checked with `# @type self: <class>`, e.g. an ERB view),
  #       # which has no method to list in `runs_before`.
  #       - class: ERBPostsShow
  #         applies_constants:
  #           Current: "singleton(Current) & Current::UserPopulated"
  #         toplevel: true
  #
  # Semantics: for each entry, at the entry of every method in `runs_before`
  # on the matching class — or, for `toplevel: true`, at the top-level body
  # of the class — Steep applies the entry's narrowing to the initial env:
  #   - `apply_postcondition_of` looks up the handler's `unconditional`
  #     postcondition (from the `.steep_postconditions.yml` machinery, issue
  #     felixefelip/steep#23) and refines `instance_variable_types`. If the
  #     handler has no `unconditional` postcondition, that part is ignored.
  #   - `applies_self` refines the method's `self` type to the given RBS type.
  #   - `applies_constants` refines the env's constant types (the same slot
  #     `@type const` annotations use), so reads of e.g. `Current` inside the
  #     method see a marker-decorated singleton.
  # An entry may carry any combination of the three.
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

      # Entries that apply to the TOP-LEVEL body of `type_name` (no method
      # — e.g. an ERB view checked with `# @type self: ERBClass`). Marked
      # `toplevel: true` in the sidecar. felixefelip/rbs_infer#25.
      def toplevel_entries(type_name)
        key = type_name.to_s.sub(/\A::/, "")
        (@entries_by_class[key] || []).select(&:toplevel)
      end
    end

    class Entry
      attr_reader :class_name, :handler_method, :applies_self, :applies_constants, :runs_before, :singleton, :toplevel, :source

      def self.parse(row, source:)
        return nil unless row.is_a?(Hash)

        klass = row["class"]
        handler = row["apply_postcondition_of"]
        applies_self = row["applies_self"]
        applies_constants = parse_constants(row["applies_constants"], source: source)
        runs_before = row["runs_before"]
        singleton = row["singleton"] == true
        # `toplevel: true` applies the narrowing to the class's top-level
        # body instead of named methods — for files checked with
        # `# @type self: <class>` (ERB views). felixefelip/rbs_infer#25.
        toplevel = row["toplevel"] == true

        return nil unless klass.is_a?(String) && !klass.empty?

        # An entry narrows in one of two ways:
        #   - apply_postcondition_of: <handler> — apply the handler's
        #     `unconditional` postcondition ivar refinements (controller
        #     before_action style).
        #   - applies_self: <RBS type> — refine `self` directly at method
        #     entry (ActiveRecord after-validation callback style, where the
        #     record is known to satisfy its validations, e.g.
        #     `Dose & Dose::Validated`).
        #   - applies_constants: { ConstName => <RBS type> } — refine how
        #     constant reads are typed inside the method (global state known
        #     to be populated by an earlier callback, e.g. CurrentAttributes).
        # At least one must be present.
        has_handler = handler.is_a?(String) && !handler.empty?
        has_self = applies_self.is_a?(String) && !applies_self.empty?
        has_constants = !applies_constants.empty?
        return nil unless has_handler || has_self || has_constants

        method_syms = (runs_before.is_a?(Array) ? runs_before : []).filter_map do |name|
          case name
          when String then name.to_sym unless name.empty?
          when Symbol then name
          else
            Steep.logger.warn { "[callbacks] runs_before entry must be a string/symbol, got #{name.inspect} in #{source}" }
            nil
          end
        end
        # A method entry needs `runs_before`; a top-level entry doesn't
        # (it applies to the class's top-level body, no method).
        return nil if method_syms.empty? && !toplevel

        new(
          class_name: klass,
          handler_method: has_handler ? handler.to_sym : nil,
          applies_self: has_self ? applies_self : nil,
          applies_constants: applies_constants,
          runs_before: method_syms,
          singleton: singleton,
          toplevel: toplevel,
          source: source
        )
      end

      # `applies_constants` must be a map of constant name → RBS type
      # string; anything else is dropped with a warning.
      def self.parse_constants(raw, source:)
        return {} unless raw.is_a?(Hash)

        raw.each_with_object({}) do |(name, type), acc|
          unless name.is_a?(String) && !name.empty? && type.is_a?(String) && !type.empty?
            Steep.logger.warn { "[callbacks] applies_constants entry must map String => String, got #{name.inspect} => #{type.inspect} in #{source}" }
            next
          end
          acc[name] = type
        end
      end

      def initialize(class_name:, handler_method: nil, applies_self: nil, applies_constants: {}, runs_before:, singleton: false, toplevel: false, source: nil)
        @class_name = class_name
        @handler_method = handler_method
        @applies_self = applies_self
        @applies_constants = applies_constants
        @runs_before = runs_before
        @singleton = singleton
        @toplevel = toplevel
        @source = source
      end
    end

    # Turns an `applies_constants` map (`{ "Current" => "singleton(Current)
    # & Current::CadernetaPopulated" }`) into `constant_types` env updates.
    # Shared by the method-entry path (TypeConstruction) and the top-level
    # path (TypeCheckService, for `# @type self:` files). Dangling marker
    # references are skipped — a sidecar emitter can race ahead of marker
    # generation, and applying an unresolvable type would crash shape
    # computation later (same tolerance as the postcondition path).
    module ConstantNarrowing
      module_function

      # => { RBS::TypeName => AST::Types::t } suitable for
      #    `type_env.merge(constant_types: ...)`.
      def constant_type_updates(applies_constants, factory:)
        updates = {} #: Hash[RBS::TypeName, AST::Types::t]
        applies_constants.each do |const_name, type_string|
          ast_type = parse_type(type_string, factory: factory)
          next unless ast_type

          type_name_keys(const_name).each { |key| updates[key] = ast_type }
        end
        updates
      end

      def parse_type(string, factory:)
        rbs_type = RBS::Parser.parse_type(string)
        return nil unless rbs_type
        return nil unless markers_resolvable?(rbs_type, factory: factory)

        factory.type(rbs_type)
      rescue StandardError => e
        Steep.logger.warn { "[callbacks] failed to parse applies_constants type #{string.inspect}: #{e.message}" }
        nil
      end

      # A constant read keyed by `Current` uses a relative TypeName; one by
      # `::Current` an absolute one — register the narrowing under both.
      def type_name_keys(const_name)
        relative = RBS::TypeName.parse(const_name.sub(/\A::/, ""))
        [relative, relative.absolute? ? relative : relative.absolute!].uniq
      end

      def markers_resolvable?(rbs_type, factory:)
        env = factory.env
        marker_names(rbs_type).all? do |name|
          absolute = name.absolute? ? name : name.absolute!
          env.class_decls.key?(absolute) || env.class_alias_decls.key?(absolute) || env.normalized_module_class_entry(absolute)
        end
      rescue StandardError
        false
      end

      def marker_names(rbs_type, acc = [])
        case rbs_type
        when RBS::Types::ClassInstance, RBS::Types::ClassSingleton
          acc << rbs_type.name
        when RBS::Types::Intersection, RBS::Types::Union
          rbs_type.types.each { |t| marker_names(t, acc) }
        when RBS::Types::Optional
          marker_names(rbs_type.type, acc)
        end
        acc
      end
    end
  end
end
