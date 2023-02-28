module Steep
  module TypeInference
    class ConstantEnv
      attr_reader :context
      attr_reader :factory
      attr_reader :resolver

      def initialize(factory:, context:, resolver:)
        @factory = factory
        @context = context
        @resolver = resolver
      end

      def resolve(name)
        decompose_constant(
          resolver.resolve(name, context: context)
        )
      end

      def toplevel(name)
        decompose_constant(
          resolver.table.toplevel[name]
        )
      end

      def constants
        cs = resolver.constants(context) or raise
        cs.transform_values {|c| decompose_constant!(c) }
      end

      def resolve_child(module_name, constant_name)
        decompose_constant(
          resolver.resolve_child(module_name, constant_name)
        )
      end

      def children(module_name)
        resolver.children(module_name).transform_values {|c| decompose_constant!(c) }
      end

      def decompose_constant!(constant)
        decompose_constant(constant) || raise
      end

      def decompose_constant(constant)
        if constant
          [
            factory.type(constant.type),
            constant.name,
            constant.entry
          ]
        end
      end
    end
  end
end
