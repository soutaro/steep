module Steep
  module Contracts
    class Writer
      def self.dump(contracts)
        new(contracts).dump
      end

      def self.write(path, contracts)
        new(contracts).write(path)
      end

      def initialize(contracts)
        @contracts = contracts
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
        methods = @contracts
          .sort_by { |contract| sort_key(contract) }
          .each_with_object({}) do |contract, hash|
            hash[contract_key(contract)] = serialize_contract(contract)
          end

        {
          "version" => SCHEMA_VERSION,
          "methods" => methods
        }
      end

      def sort_key(contract)
        [contract.type_name, contract.singleton ? 1 : 0, contract.method_name.to_s]
      end

      def contract_key(contract)
        separator = contract.singleton ? "." : "#"
        "#{contract.type_name}#{separator}#{contract.method_name}"
      end

      def serialize_contract(contract)
        payload = { "requires" => contract.requires.map { |req| serialize_predicate(req) } }
        # Only emit `enforced` when false; absence means enforced (the common
        # case) and keeps sidecars stable/back-compatible.
        payload["enforced"] = false unless contract.enforced
        payload
      end

      def serialize_predicate(predicate)
        case predicate
        when Predicate::NotNil
          { "kind" => "not_nil", "expr" => serialize_expr(predicate.expr) }
        else
          raise ArgumentError, "Unsupported predicate: #{predicate.class}"
        end
      end

      def serialize_expr(expr)
        case expr
        when Expr::SelfRef
          { "kind" => "self" }
        when Expr::Send
          payload = {
            "kind" => "send",
            "receiver" => serialize_expr(expr.receiver),
            "method" => expr.method.to_s
          }
          payload["chain"] = expr.chain.map(&:to_s) unless expr.chain.empty?
          payload
        else
          raise ArgumentError, "Unsupported expression: #{expr.class}"
        end
      end
    end
  end
end
