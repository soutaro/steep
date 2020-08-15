module Steep
  module TypeInference
    class ConstantEnv
      attr_reader :context
      attr_reader :cache
      attr_reader :factory
      attr_reader :table

      # ConstantEnv receives an Names::Module as a context, not a Namespace, because this is a simulation of Ruby.
      # Any namespace is a module or class.
      def initialize(factory:, context:)
        @cache = {}
        @factory = factory
        @context = context
        @table = RBS::ConstantTable.new(builder: factory.definition_builder)
      end

      def lookup(name)
        cache[name] ||= begin
          constant = table.resolve_constant_reference(
            factory.type_name_1(name),
            context: context.map {|namespace| factory.namespace_1(namespace) }
          )

          if constant
            factory.type(constant.type)
          end
        rescue => exn
          Steep.logger.debug "Looking up a constant failed: name=#{name}, context=[#{context.join(", ")}], error=#{exn.inspect}"
          nil
        end
      end
    end
  end
end
