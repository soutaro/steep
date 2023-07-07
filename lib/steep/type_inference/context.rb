module Steep
  module TypeInference
    class Context
      class MethodContext
        attr_reader :name
        attr_reader :method
        attr_reader :method_type
        attr_reader :return_type
        attr_reader :super_method
        attr_reader :forward_arg_type

        def initialize(name:, method:, method_type:, return_type:, super_method:, forward_arg_type:)
          @name = name
          @method = method
          @return_type = return_type
          @method_type = method_type
          @super_method = super_method
          @forward_arg_type = forward_arg_type
        end

        def block_type
          method_type&.block
        end

        def attribute_setter?
          name.to_s.end_with?('=')
        end
      end

      class BlockContext
        attr_reader :body_type

        def initialize(body_type:)
          @body_type = body_type
        end

        def subst(s)
          BlockContext.new(body_type: body_type&.subst(s))
        end
      end

      class BreakContext
        attr_reader :break_type
        attr_reader :next_type

        def initialize(break_type:, next_type:)
          @break_type = break_type
          @next_type = next_type
        end

        def subst(s)
          BreakContext.new(break_type: break_type.subst(s), next_type: next_type&.subst(s))
        end
      end

      class ModuleContext
        attr_reader :instance_type
        attr_reader :module_type
        attr_reader :defined_instance_methods
        attr_reader :defined_module_methods
        attr_reader :nesting
        attr_reader :implement_name
        attr_reader :class_name
        attr_reader :instance_definition
        attr_reader :module_definition

        def initialize(instance_type:, module_type:, implement_name:, class_name:, instance_definition: nil, module_definition: nil, nesting:)
          @instance_type = instance_type
          @module_type = module_type
          @defined_instance_methods = Set.new
          @defined_module_methods = Set.new
          @implement_name = implement_name
          @nesting = nesting
          @class_name = class_name
          @instance_definition = instance_definition
          @module_definition = module_definition
        end

        def class_variables
          if module_definition
            @class_variables ||= module_definition.class_variables.transform_values do |var_def|
              var_def.type
            end
          end
        end

        def update(
          instance_type: self.instance_type,
          module_type: self.module_type,
          implement_name: self.implement_name,
          class_name: self.class_name,
          instance_definition: self.instance_definition,
          module_definition: self.module_definition,
          nesting: self.nesting
        )
          ModuleContext.new(
            instance_type: instance_type,
            module_type: module_type,
            implement_name: implement_name,
            nesting: nesting,
            class_name: class_name,
            instance_definition: instance_definition,
            module_definition: module_definition
          )
        end
      end

      class TypeVariableContext
        attr_reader :table
        attr_reader :type_params

        def initialize(type_params, parent_context: nil)
          @type_params = type_params

          @table = {}
          table.merge!(parent_context.table) if parent_context

          type_params.each do |param|
            table[param.name] = param
          end
        end

        def [](name)
          table[name].upper_bound
        end

        def upper_bounds
          table.each_value.with_object({}) do |type_param, bounds|
            if type_param.upper_bound
              bounds[type_param.name] = type_param.upper_bound
            end
          end
        end

        def self.empty
          new([])
        end
      end

      attr_reader :call_context
      attr_reader :method_context
      attr_reader :block_context
      attr_reader :break_context
      attr_reader :module_context
      attr_reader :self_type
      attr_reader :type_env
      attr_reader :variable_context

      def initialize(method_context:, block_context:, break_context:, module_context:, self_type:, type_env:, call_context:, variable_context:)
        @method_context = method_context
        @block_context = block_context
        @break_context = break_context
        @module_context = module_context
        @self_type = self_type
        @type_env = type_env
        @call_context = call_context
        @variable_context = variable_context
      end

      def with(method_context: self.method_context,
               block_context: self.block_context,
               break_context: self.break_context,
               module_context: self.module_context,
               self_type: self.self_type,
               type_env: self.type_env,
               call_context: self.call_context,
               variable_context: self.variable_context)
        self.class.new(
          method_context: method_context,
          block_context: block_context,
          break_context: break_context,
          module_context: module_context,
          self_type: self_type,
          type_env: type_env,
          call_context: call_context,
          variable_context: variable_context
        )
      end

      def inspect
        s = "#<%s:%#018x " % [self.class, object_id]
        s << instance_variables.map(&:to_s).sort.map {|name| "#{name}=..." }.join(", ")
        s + ">"
      end

      def factory
        type_env.constant_env.factory
      end

      def env
        factory.env
      end
    end
  end
end
