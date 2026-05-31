module Steep
  module Contracts
    DEFAULT_SIDECAR_PATH = "sig/generated/.steep_contracts.yml".freeze
    SCHEMA_VERSION = 1

    class << self
      def load(base_dir, path: DEFAULT_SIDECAR_PATH)
        absolute = base_dir + path
        return Store.empty unless absolute.file?

        raw = YAML.safe_load(absolute.read, aliases: false)
        Store.from_hash(raw, source: absolute.to_s)
      rescue Psych::SyntaxError, LoadError => e
        Steep.logger.warn { "[contracts] failed to parse #{absolute}: #{e.message}" }
        Store.empty
      end
    end

    class Store
      attr_reader :methods, :source

      def self.empty
        new(methods: {}, source: nil)
      end

      def self.from_hash(raw, source:)
        version = raw && raw["version"]
        if version && version != SCHEMA_VERSION
          Steep.logger.warn { "[contracts] unsupported sidecar version #{version} (expected #{SCHEMA_VERSION}); ignoring #{source}" }
          return empty
        end

        entries = (raw && raw["methods"]) || {}
        methods = {} #: Hash[String, MethodContract]
        entries.each do |key, payload|
          contract = MethodContract.parse(key, payload, source: source)
          methods[key] = contract if contract
        end
        new(methods: methods, source: source)
      end

      def initialize(methods:, source:)
        @methods = methods
        @source = source
      end

      def empty?
        @methods.empty?
      end

      def lookup_instance(type_name, method_name)
        @methods["#{type_name}##{method_name}"]
      end

      def lookup_singleton(type_name, method_name)
        @methods["#{type_name}.#{method_name}"]
      end
    end

    class MethodContract
      KEY_PATTERN = /\A(?<type>[A-Z][\w:]*)(?<kind>[#.])(?<method>[\w!?=\[\]<>+\-*\/%&|^~]+)\z/.freeze

      attr_reader :type_name, :method_name, :singleton, :requires, :enforced

      def self.parse(key, payload, source:)
        match = KEY_PATTERN.match(key)
        unless match
          Steep.logger.warn { "[contracts] invalid method key #{key.inspect} in #{source}" }
          return nil
        end

        requires_raw = (payload && payload["requires"]) || []
        requires = requires_raw.filter_map { |r| Predicate.parse(r, source: source) }
        return nil if requires.empty?

        # `enforced` defaults to true so sidecars written before this flag
        # existed keep narrowing on (no behavior change on upgrade).
        enforced = payload.key?("enforced") ? payload["enforced"] != false : true

        new(
          type_name: match[:type],
          method_name: match[:method].to_sym,
          singleton: match[:kind] == ".",
          requires: requires,
          enforced: enforced
        )
      end

      def initialize(type_name:, method_name:, singleton:, requires:, enforced: true)
        @type_name = type_name
        @method_name = method_name
        @singleton = singleton
        @requires = requires
        @enforced = enforced
      end

      def key
        "#{type_name}#{singleton ? '.' : '#'}#{method_name}"
      end

      def with_enforced(value)
        MethodContract.new(
          type_name: type_name,
          method_name: method_name,
          singleton: singleton,
          requires: requires,
          enforced: value
        )
      end
    end

    module Predicate
      def self.parse(raw, source:)
        case raw["kind"]
        when "not_nil"
          expr = Expr.parse(raw["expr"], source: source)
          NotNil.new(expr) if expr
        else
          Steep.logger.warn { "[contracts] unknown predicate kind #{raw["kind"].inspect} in #{source}" }
          nil
        end
      end

      class NotNil
        attr_reader :expr

        def initialize(expr)
          @expr = expr
        end
      end
    end

    module Expr
      def self.parse(raw, source:)
        case raw["kind"]
        when "self"
          SelfRef.instance
        when "send"
          receiver = parse(raw["receiver"], source: source)
          return nil unless receiver
          method = raw["method"]
          return nil unless method
          chain = (raw["chain"] || []).map(&:to_sym)
          Send.new(receiver: receiver, method: method.to_sym, chain: chain)
        else
          Steep.logger.warn { "[contracts] unknown expr kind #{raw["kind"].inspect} in #{source}" }
          nil
        end
      end

      class SelfRef
        def self.instance
          @instance ||= new
        end
      end

      class Send
        attr_reader :receiver, :method, :chain

        def initialize(receiver:, method:, chain:)
          @receiver = receiver
          @method = method
          @chain = chain
        end
      end
    end
  end
end
