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
        @table = Ruby::Signature::ConstantTable.new(builder: factory.definition_builder)
      end

      def namespace
        @namespace ||= if context
                         context.namespace.append(context.name)
                       else
                         AST::Namespace.root
                       end
      end

      def lookup(name)
        cache[name] ||= begin
          constant = table.resolve_constant_reference(
            factory.type_name_1(name),
            context: factory.namespace_1(namespace)
          )

          if constant
            factory.type(constant.type)
          end
        end
      end
    end
  end
end
