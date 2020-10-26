module Steep
  module TypeInference
    class Context
      class MethodContext
        attr_reader :name
        attr_reader :method
        attr_reader :method_type
        attr_reader :return_type
        attr_reader :constructor
        attr_reader :super_method

        def initialize(name:, method:, method_type:, return_type:, constructor:, super_method:)
          @name = name
          @method = method
          @return_type = return_type
          @method_type = method_type
          @constructor = constructor
          @super_method = super_method
        end

        def block_type
          method_type&.block
        end
      end

      class BlockContext
        attr_reader :body_type

        def initialize(body_type:)
          @body_type = body_type
        end
      end

      class BreakContext
        attr_reader :break_type
        attr_reader :next_type

        def initialize(break_type:, next_type:)
          @break_type = break_type
          @next_type = next_type
        end
      end

      class ModuleContext
        attr_reader :instance_type
        attr_reader :module_type
        attr_reader :defined_instance_methods
        attr_reader :defined_module_methods
        attr_reader :const_env
        attr_reader :implement_name
        attr_reader :namespaces
        attr_reader :current_namespace
        attr_reader :class_name
        attr_reader :instance_definition
        attr_reader :module_definition

        def initialize(instance_type:, module_type:, implement_name:, current_namespace:, const_env:, class_name:, instance_definition: nil, module_definition: nil)
          @instance_type = instance_type
          @module_type = module_type
          @defined_instance_methods = Set.new
          @defined_module_methods = Set.new
          @implement_name = implement_name
          @current_namespace = current_namespace
          @const_env = const_env
          @class_name = class_name
          @instance_definition = instance_definition
          @module_definition = module_definition
        end

        def const_context
          const_env.context
        end

        def class_variables
          if module_definition
            @class_variables ||= module_definition.class_variables.transform_values do |var_def|
              var_def.type
            end
          end
        end
      end

      attr_reader :call_context
      attr_reader :method_context
      attr_reader :block_context
      attr_reader :break_context
      attr_reader :module_context
      attr_reader :self_type
      attr_reader :type_env
      attr_reader :lvar_env

      def initialize(method_context:, block_context:, break_context:, module_context:, self_type:, type_env:, lvar_env:, call_context:)
        @method_context = method_context
        @block_context = block_context
        @break_context = break_context
        @module_context = module_context
        @self_type = self_type
        @type_env = type_env
        @lvar_env = lvar_env
        @call_context = call_context
      end

      def with(method_context: self.method_context,
               block_context: self.block_context,
               break_context: self.break_context,
               module_context: self.module_context,
               self_type: self.self_type,
               type_env: self.type_env,
               lvar_env: self.lvar_env,
               call_context: self.call_context)
        self.class.new(
          method_context: method_context,
          block_context: block_context,
          break_context: break_context,
          module_context: module_context,
          self_type: self_type,
          type_env: type_env,
          lvar_env: lvar_env,
          call_context: call_context
        )
      end
    end
  end
end
