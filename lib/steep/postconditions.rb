module Steep
  # Conditional postconditions sidecar (issue felixefelip/steep#10).
  #
  # Loads `.steep_postconditions.yml`, a sidecar produced by rbs_rails (and
  # any other source) that declares, per `(class, method)` pair, how the
  # receiver should be refined in the truthy/falsy branches of a boolean
  # call. The intent mirrors `Steep::Contracts` (preconditions): keep the
  # extension out of the RBS grammar by emitting a YAML file the checker
  # consumes at type-check time.
  #
  # Schema:
  #
  #     ---
  #     postconditions:
  #       - class: OrderImport
  #         method: shipment?
  #         when_true:
  #           self: OrderImport & OrderImport::ValidatedAsShipment
  #         when_false:
  #           self: OrderImport
  #
  # `when_true` / `when_false` are independent and optional. The `self:`
  # type string is parsed lazily via `RBS::Parser.parse_type`.
  module Postconditions
    # Glob (relative to `base_dir`) used to discover sidecar files. Unlike
    # the single-file `Steep::Contracts`, postconditions are written by
    # external generators (rbs_rails, rbs_inline, hand-authored…) that all
    # land under `sig/`, so the loader scans recursively and merges
    # entries.
    DEFAULT_SIDECAR_GLOB = "sig/**/.steep_postconditions.yml".freeze

    class << self
      def load(base_dir, glob: DEFAULT_SIDECAR_GLOB)
        paths = Dir.glob(File.join(base_dir.to_s, glob)).sort
        return Store.empty if paths.empty?

        merged = {} #: Hash[[String, Symbol], Entry]
        sources = []

        paths.each do |path|
          absolute = Pathname.new(path)
          raw = YAML.safe_load(absolute.read, aliases: true)
          next unless raw

          sub = Store.from_hash(raw, source: absolute.to_s)
          sub.entries.each do |key, entry|
            if merged.key?(key)
              Steep.logger.warn { "[postconditions] duplicate entry for #{key.first}##{key.last} across files; keeping first (#{merged[key].class}); ignoring #{absolute}" }
              next
            end
            merged[key] = entry
          end
          sources << absolute.to_s
        rescue Psych::Exception, LoadError => e
          Steep.logger.warn { "[postconditions] failed to parse #{absolute}: #{e.message}" }
        end

        Store.new(entries: merged, source: sources.join(", "))
      end
    end

    class Store
      attr_reader :entries, :source

      def self.empty
        new(entries: {}, source: nil)
      end

      def self.from_hash(raw, source:)
        rows = (raw && raw["postconditions"]) || []
        index = {} #: Hash[[String, Symbol], Entry]
        rows.each do |row|
          entry = Entry.parse(row, source: source)
          next unless entry
          key = [entry.class_name, entry.method_name]
          if index.key?(key)
            Steep.logger.warn { "[postconditions] duplicate entry for #{entry.class_name}##{entry.method_name} in #{source}; keeping first" }
            next
          end
          index[key] = entry
        end
        new(entries: index, source: source)
      end

      def initialize(entries:, source:)
        @entries = entries
        @source = source
      end

      def empty?
        @entries.empty?
      end

      def lookup_instance(type_name, method_name)
        @entries[[type_name.to_s.sub(/\A::/, ""), method_name.to_sym]]
      end
    end

    class Entry
      attr_reader :class_name, :method_name, :when_true, :when_false, :unconditional

      def self.parse(row, source:)
        return nil unless row.is_a?(Hash)
        klass = row["class"]
        method = row["method"]
        return nil unless klass && method

        when_true = Branch.parse(row["when_true"], source: source)
        when_false = Branch.parse(row["when_false"], source: source)
        # `unconditional:` fires at every call site of the method, with no
        # regard for whether the return value is used as a guard. Carries
        # the same shape as `when_true`/`when_false` (`self`, `via_receiver`,
        # `ivars`) so a single mechanism covers three patterns:
        #
        #   - `update!`-style bang on a receiver: `unconditional.self`
        #     narrows the receiver after the call (raises on failure, so if
        #     it returned, the invariant holds).
        #   - `set_company`-style side-effect method: `unconditional.ivars`
        #     narrows the caller's ivar that the method assigned to.
        #   - both at once for methods that mutate the receiver *and* set
        #     another caller ivar.
        unconditional = Branch.parse(row["unconditional"], source: source)
        return nil unless when_true || when_false || unconditional

        new(
          class_name: klass.to_s,
          method_name: method.to_sym,
          when_true: when_true,
          when_false: when_false,
          unconditional: unconditional
        )
      end

      def initialize(class_name:, method_name:, when_true:, when_false:, unconditional: nil)
        @class_name = class_name
        @method_name = method_name
        @when_true = when_true
        @when_false = when_false
        @unconditional = unconditional
      end
    end

    class Branch
      attr_reader :self_type_string, :via_receivers, :ivar_type_strings, :drops_type_strings

      def self.parse(raw, source:)
        return nil unless raw.is_a?(Hash)
        self_str = raw["self"]
        via_receivers = parse_via_receivers(raw["via_receiver"], source: source)
        ivars = parse_ivars(raw["ivars"], source: source)
        drops = parse_drops(raw["drops"], source: source)
        has_content = (self_str.is_a?(String) && !self_str.empty?) ||
                      via_receivers.any? ||
                      ivars.any? ||
                      drops.any?
        return nil unless has_content

        new(self_type_string: self_str, via_receivers: via_receivers, ivar_type_strings: ivars, drops_type_strings: drops)
      end

      def self.parse_via_receivers(raw, source:)
        return [] unless raw.is_a?(Array)
        raw.filter_map { |entry| ViaReceiver.parse(entry, source: source) }
      end

      # Parses `drops:` payload — a list of type-name strings whose
      # markers should be subtracted from the receiver type when the
      # branch fires (felixefelip/steep#29). Used primarily on
      # `when_false` to express "this predicate returning false means
      # the receiver lost these markers" — something pure intersection
      # (the `self:` slot) can't capture.
      #
      # Schema accepts an Array of strings. Empty list or non-Array
      # input is treated as "no drops".
      def self.parse_drops(raw, source:)
        return [] unless raw.is_a?(Array)
        raw.filter_map do |entry|
          if entry.is_a?(String) && !entry.empty?
            entry
          else
            Steep.logger.warn { "[postconditions] drops entry must be a non-empty type-name string, got #{entry.inspect} (#{source})" }
            nil
          end
        end
      end

      # Parses `ivars:` payload — a hash mapping ivar names (with the leading
      # `@`) to RBS type strings, e.g. `{ "@company": "Company & Validated" }`.
      # Entries with non-string values or empty keys are dropped with a warn.
      def self.parse_ivars(raw, source:)
        return {} unless raw.is_a?(Hash)
        result = {} #: Hash[Symbol, String]
        raw.each do |name, type_str|
          unless name.is_a?(String) && name.start_with?("@")
            Steep.logger.warn { "[postconditions] ivars: key must be a string starting with `@`, got #{name.inspect} (#{source})" }
            next
          end
          unless type_str.is_a?(String) && !type_str.empty?
            Steep.logger.warn { "[postconditions] ivars: value must be a non-empty type string, got #{type_str.inspect} for #{name} (#{source})" }
            next
          end
          result[name.to_sym] = type_str
        end
        result
      end

      def initialize(self_type_string:, via_receivers: [], ivar_type_strings: {}, drops_type_strings: [])
        @self_type_string = self_type_string
        @via_receivers = via_receivers
        @ivar_type_strings = ivar_type_strings
        @drops_type_strings = drops_type_strings
      end

      # Parses the YAML `self:` payload into an `RBS::Types::t`. Cached so
      # repeated lookups (the same predicate called many times) don't keep
      # re-parsing. Returns `nil` if the string fails to parse or if no
      # `self:` was declared (the branch may have only `via_receiver` or
      # `ivars`).
      def rbs_type
        return @rbs_type if defined?(@rbs_type)
        @rbs_type =
          if self_type_string.is_a?(String) && !self_type_string.empty?
            begin
              RBS::Parser.parse_type(self_type_string)
            rescue RBS::ParsingError => e
              Steep.logger.warn { "[postconditions] failed to parse self type #{self_type_string.inspect}: #{e.message}" }
              nil
            end
          end
      end

      # Lazy-parsed RBS types for the `drops:` slot. Each entry is
      # expected to be a class/module reference (the marker to drop);
      # complex types are accepted by the parser but only
      # ClassInstance/Interface names are used at apply time.
      def drops_rbs_types
        return @drops_rbs_types if defined?(@drops_rbs_types)
        @drops_rbs_types = drops_type_strings.filter_map do |type_str|
          begin
            RBS::Parser.parse_type(type_str)
          rescue RBS::ParsingError => e
            Steep.logger.warn { "[postconditions] failed to parse drops type #{type_str.inspect}: #{e.message}" }
            nil
          end
        end
      end

      # Lazy-parsed `Hash[Symbol, RBS::Types::t]` for the `ivars:` slot.
      # Cached so a method called many times doesn't keep re-parsing.
      # Entries that fail to parse are dropped with a warning.
      def ivar_rbs_types
        return @ivar_rbs_types if defined?(@ivar_rbs_types)
        @ivar_rbs_types = ivar_type_strings.each_with_object({}) do |(name, type_str), hash|
          begin
            hash[name] = RBS::Parser.parse_type(type_str)
          rescue RBS::ParsingError => e
            Steep.logger.warn { "[postconditions] failed to parse ivars[#{name}] type #{type_str.inspect}: #{e.message}" }
          end
        end
      end
    end

    # Refinement of a receiver other than `self`, indexed by the immediate
    # receiver's method (`through:`). When the predicate is called like
    # `host.<through_method>.<predicate>`, the receiver-of-receiver (`host`)
    # is intersected with `as:`. This is felixefelip/steep#14.
    class ViaReceiver
      attr_reader :through_string, :as_type_string

      def self.parse(raw, source:)
        return nil unless raw.is_a?(Hash)
        through = raw["through"]
        as_str = raw["as"]
        return nil unless through.is_a?(String) && as_str.is_a?(String)
        return nil if through.empty? || as_str.empty?
        return nil unless through.include?("#")
        new(through_string: through, as_type_string: as_str)
      end

      def initialize(through_string:, as_type_string:)
        @through_string = through_string
        @as_type_string = as_type_string
      end

      # `"Order#order_import"` → `RBS::TypeName.parse("::Order")`
      def through_type_name
        return @through_type_name if defined?(@through_type_name)
        @through_type_name =
          begin
            type_str, _ = through_string.split("#", 2)
            RBS::TypeName.parse(type_str.to_s).absolute!
          rescue RBS::ParsingError, StandardError => e
            Steep.logger.warn { "[postconditions] failed to parse via_receiver through #{through_string.inspect}: #{e.message}" }
            nil
          end
      end

      # `"Order#order_import"` → `:order_import`
      def through_method_name
        return @through_method_name if defined?(@through_method_name)
        @through_method_name = through_string.split("#", 2).last&.to_sym
      end

      # `"Order & Order::Validated"` → `RBS::Types::Intersection(...)`
      def as_rbs_type
        return @as_rbs_type if defined?(@as_rbs_type)
        @as_rbs_type =
          begin
            RBS::Parser.parse_type(as_type_string)
          rescue RBS::ParsingError => e
            Steep.logger.warn { "[postconditions] failed to parse via_receiver as #{as_type_string.inspect}: #{e.message}" }
            nil
          end
      end
    end
  end
end
