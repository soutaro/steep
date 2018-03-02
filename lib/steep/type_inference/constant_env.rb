module Steep
  module TypeInference
    class ConstantEnv
      attr_reader :signatures
      attr_reader :current_namespace
      attr_reader :cache

      def initialize(signatures:, current_namespace:)
        @cache = {}
        @signatures = signatures
        @current_namespace = current_namespace
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
          end
        else
          if namespace
            case
            when signatures.module_name?(name, current_module: namespace)
              AST::Types::Name.new_module(name: namespace + name)
            when signatures.class_name?(name, current_module: namespace)
              AST::Types::Name.new_class(name: namespace + name, constructor: true)
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
