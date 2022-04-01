module Steep
  module TypeInference
    class ConstantEnv
      attr_reader :context
      attr_reader :factory
      attr_reader :resolver
      attr_reader :resolver_context

      # ConstantEnv receives an TypeName as a context, not a Namespace, because this is a simulation of Ruby.
      # Any namespace is a module or class.
      def initialize(factory:, context:, resolver:)
        @cache = {}
        @factory = factory
        @context = context
        @resolver_context = context.
          reject {|ns| ns == RBS::Namespace.root }.
          reverse_each.
          inject(nil) {|context, ns| [context, ns ? ns.to_type_name : false] }
        @resolver = resolver
      end

      def resolve(name)
        decompose_constant(
          resolver.resolve(name, context: resolver_context)
        )
      end

      def toplevel(name)
        decompose_constant(
          resolver.table.toplevel[name]
        )
      end

      def constants
        resolver.constants(resolver_context).transform_values {|c| decompose_constant(c) }
      end

      def resolve_child(module_name, constant_name)
        decompose_constant(
          resolver.resolve_child(module_name, constant_name)
        )
      end

      def children(module_name)
        resolver.children(module_name).transform_values {|c| decompose_constant(c) }
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
