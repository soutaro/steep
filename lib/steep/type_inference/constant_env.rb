module Steep
  module TypeInference
    class ConstantEnv
      attr_reader :builder
      attr_reader :context
      attr_reader :cache

      # ConstantEnv receives an optional ModuleName, not a Namespace, because this is a simulation of Ruby.
      # Any namespace is a module or class.
      def initialize(builder:, context:)
        @cache = {}
        @builder = builder
        @context = context
      end

      def signatures
        builder.signatures
      end

      def namespace
        @namespace ||= if context
                         context.namespace.append(context.name)
                       else
                         AST::Namespace.root
                       end
      end

      def lookup(name)
        cache[name] ||= lookup0(name, namespace: namespace)
      end

      # @type method lookup0: (ModuleName, namespace: AST::Namespace) -> Type
      def lookup0(name, namespace:)
        full_name = name.in_namespace(namespace)
        case
        when signatures.module_name?(full_name)
          AST::Types::Name.new_module(name: full_name)
        when signatures.class_name?(full_name)
          AST::Types::Name.new_class(name: full_name, constructor: true)
        when signatures.const_name?(full_name)
          builder.absolute_type(signatures.find_const(name, current_module: namespace).type,
                                current: namespace)
        else
          unless namespace.empty?
            lookup0(name, namespace: namespace.parent)
          end
        end
      end
    end
  end
end
