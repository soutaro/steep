module Steep
  module TypeInference
    class ConstantEnv
      attr_reader :builder
      attr_reader :current_namespace
      attr_reader :cache

      def initialize(builder:, current_namespace:)
        @cache = {}
        @builder = builder
        @current_namespace = current_namespace
      end

      def signatures
        builder.signatures
      end

      def lookup(name)
        unless cache.key?(name)
          cache[name] = lookup0(name, namespace: current_namespace)
        end

        cache[name]
      end

      def lookup0(name, namespace:)
        if name.absolute?
          case
          when signatures.module_name?(name)
            AST::Types::Name.new_module(name: name)
          when signatures.class_name?(name)
            AST::Types::Name.new_class(name: name, constructor: true)
          when signatures.const_name?(name)
            builder.absolute_type(signatures.find_const(name).type, current: nil)
          end
        else
          if namespace
            case
            when signatures.module_name?(name, current_module: namespace)
              AST::Types::Name.new_module(name: namespace + name)
            when signatures.class_name?(name, current_module: namespace)
              AST::Types::Name.new_class(name: namespace + name, constructor: true)
            when signatures.const_name?(name, current_module: namespace)
              builder.absolute_type(signatures.find_const(name, current_module: namespace).type, current: nil)
            else
              lookup0(name, namespace: namespace.parent)
            end
          else
            lookup0(name.absolute!, namespace: nil)
          end
        end
      end
    end
  end
end
