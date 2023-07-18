module Steep
  module TypeInference
    class TypeEnv
      include NodeHelper

      attr_reader :local_variable_types
      attr_reader :instance_variable_types, :global_types, :constant_types
      attr_reader :constant_env
      attr_reader :pure_method_calls

      def to_s
        array = [] #: Array[String]

        local_variable_types.each do |name, entry|
          if enforced_type = entry[1]
            array << "#{name}: #{entry[0].to_s} <#{enforced_type.to_s}>"
          else
            array << "#{name}: #{entry[0].to_s}"
          end
        end

        instance_variable_types.each do |name, type|
          array << "#{name}: #{type.to_s}"
        end

        global_types.each do |name, type|
          array << "#{name}: #{type.to_s}"
        end

        constant_types.each do |name, type|
          array << "#{name}: #{type.to_s}"
        end

        pure_method_calls.each do |node, pair|
          call, type = pair
          array << "`#{node.loc.expression.source.lines[0]}`: #{type || call.return_type}"
        end

        "{ #{array.join(", ")} }"
      end

      def initialize(constant_env, local_variable_types: {}, instance_variable_types: {}, global_types: {}, constant_types: {}, pure_method_calls: {})
        @constant_env = constant_env
        @local_variable_types = local_variable_types
        @instance_variable_types = instance_variable_types
        @global_types = global_types
        @constant_types = constant_types
        @pure_method_calls = pure_method_calls

        @pure_node_descendants = {}
      end

      def update(local_variable_types: self.local_variable_types, instance_variable_types: self.instance_variable_types, global_types: self.global_types, constant_types: self.constant_types, pure_method_calls: self.pure_method_calls)
        TypeEnv.new(
          constant_env,
          local_variable_types: local_variable_types,
          instance_variable_types: instance_variable_types,
          global_types: global_types,
          constant_types: constant_types,
          pure_method_calls: pure_method_calls
        )
      end

      def merge(local_variable_types: {}, instance_variable_types: {}, global_types: {}, constant_types: {}, pure_method_calls: {})
        local_variable_types = self.local_variable_types.merge(local_variable_types)
        instance_variable_types = self.instance_variable_types.merge(instance_variable_types)
        global_types = self.global_types.merge(global_types)
        constant_types = self.constant_types.merge(constant_types)
        pure_method_calls = self.pure_method_calls.merge(pure_method_calls)

        TypeEnv.new(
          constant_env,
          local_variable_types: local_variable_types,
          instance_variable_types: instance_variable_types,
          global_types:  global_types,
          constant_types: constant_types,
          pure_method_calls: pure_method_calls
        )
      end

      def [](name)
        case name
        when Symbol
          case
          when local_variable_name?(name)
            local_variable_types[name]&.[](0)
          when instance_variable_name?(name)
            instance_variable_types[name]
          when global_name?(name)
            global_types[name]
          else
            raise "Unexpected variable name: #{name}"
          end
        when Parser::AST::Node
          case name.type
          when :lvar
            self[name.children[0]]
          when :send
            if (call, type = pure_method_calls[name])
              type || call.return_type
            end
          end
        end
      end

      def enforced_type(name)
        local_variable_types[name]&.[](1)
      end

      def assign_local_variables(assignments)
        local_variable_types = {} #: Hash[Symbol, local_variable_entry]
        invalidated_nodes = Set[]

        assignments.each do |name, new_type|
          local_variable_name!(name)

          local_variable_types[name] = [new_type, enforced_type(name)]
          invalidated_nodes.merge(invalidated_pure_nodes(::Parser::AST::Node.new(:lvar, [name])))
        end

        invalidation = pure_node_invalidation(invalidated_nodes)

        merge(
          local_variable_types: local_variable_types,
          pure_method_calls: invalidation
        )
      end

      def assign_local_variable(name, var_type, enforced_type)
        local_variable_name!(name)
        merge(
          local_variable_types: { name => [enforced_type || var_type, enforced_type] },
          pure_method_calls: pure_node_invalidation(invalidated_pure_nodes(::Parser::AST::Node.new(:lvar, [name])))
        )
      end

      def refine_types(local_variable_types: {}, pure_call_types: {})
        local_variable_updates = {} #: Hash[Symbol, local_variable_entry]

        local_variable_types.each do |name, type|
          local_variable_name!(name)
          local_variable_updates[name] = [type, enforced_type(name)]
        end

        invalidated_nodes = Set.new(pure_call_types.each_key)
        local_variable_types.each_key do |name|
          invalidated_nodes.merge(invalidated_pure_nodes(Parser::AST::Node.new(:lvar, [name])))
        end

        pure_call_updates = pure_node_invalidation(invalidated_nodes)

        pure_call_types.each do |node, type|
          call, _ = pure_call_updates[node]
          pure_call_updates[node] = [call, type]
        end

        merge(local_variable_types: local_variable_updates, pure_method_calls: pure_call_updates)
      end

      def constant(arg1, arg2)
        if arg1.is_a?(RBS::TypeName) && arg2.is_a?(Symbol)
          constant_env.resolve_child(arg1, arg2)
        elsif arg1.is_a?(Symbol)
          if arg2
            constant_env.toplevel(arg1)
          else
            constant_env.resolve(arg1)
          end
        end
      end

      def annotated_constant(name)
        constant_types[name]
      end

      def pin_local_variables(names)
        names = Set.new(names) if names

        local_variable_types.each.with_object({}) do |pair, hash|
          name, entry = pair

          local_variable_name!(name)

          if names.nil? || names.include?(name)
            type, enforced_type = entry
            unless enforced_type
              hash[name] = [type, type]
            end
          end
        end
      end

      def unpin_local_variables(names)
        names = Set.new(names) if names

        local_var_types = local_variable_types.each.with_object({}) do |pair, hash|
          name, entry = pair

          local_variable_name!(name)

          if names.nil? || names.include?(name)
            type, _ = entry
            hash[name] = [type, nil]
          end
        end

        merge(local_variable_types: local_var_types)
      end

      def subst(s)
        update(
          local_variable_types: local_variable_types.transform_values do |entry|
            # @type block: local_variable_entry

            type, enforced_type = entry
            [
              type.subst(s),
              enforced_type&.yield_self {|ty| ty.subst(s) }
            ]
          end
        )
      end

      def join(*envs)
        # @type var all_lvar_types: Hash[Symbol, Array[AST::Types::t]]
        all_lvar_types = envs.each_with_object({}) do |env, hash|
          env.local_variable_types.each_key do |name|
            hash[name] = []
          end
        end

        envs.each do |env|
          all_lvar_types.each_key do |name|
            all_lvar_types[name] << (env[name] || AST::Builtin.nil_type)
          end
        end

        assignments =
          all_lvar_types
            .transform_values {|types| AST::Types::Union.build(types: types) }
            .reject {|var, type| self[var] == type }

        common_pure_nodes = envs
          .map {|env| Set.new(env.pure_method_calls.each_key) }
          .inject {|s1, s2| s1.intersection(s2) } || Set[]

        pure_call_updates = common_pure_nodes.each_with_object({}) do |node, hash|
          pairs = envs.map {|env| env.pure_method_calls[node] }
          refined_type = AST::Types::Union.build(types: pairs.map {|call, type| type || call.return_type })

          # Any *pure_method_call* can be used because it's *pure*
          (call, _ = envs[0].pure_method_calls[node]) or raise

          hash[node] = [call, refined_type]
        end

        assign_local_variables(assignments).merge(pure_method_calls: pure_call_updates)
      end

      def add_pure_call(node, call, type)
        if (c, _ = pure_method_calls[node]) && c == call
          return self
        end

        update =
          pure_node_invalidation(invalidated_pure_nodes(node))
            .merge!({ node => [call, type] })

        merge(pure_method_calls: update)
      end

      def replace_pure_call_type(node, type)
        if (call, _ = pure_method_calls[node])
          calls = pure_method_calls.dup
          calls[node] = [call, type]
          update(pure_method_calls: calls)
        else
          raise
        end
      end

      def invalidate_pure_node(node)
        merge(pure_method_calls: pure_node_invalidation(invalidated_pure_nodes(node)))
      end

      def pure_node_invalidation(invalidated_nodes)
        # @type var invalidation: Hash[Parser::AST::Node, [MethodCall::Typed, AST::Types::t?]]
        invalidation = {}

        invalidated_nodes.each do |node|
          if (call, _ = pure_method_calls[node])
            invalidation[node] = [call, nil]
          end
        end

        invalidation
      end

      def invalidated_pure_nodes(invalidated_node)
        invalidated_nodes = Set[]

        pure_method_calls.each_key do |pure_node|
          descendants = @pure_node_descendants[pure_node] ||= each_descendant_node(pure_node).to_set
          if descendants.member?(invalidated_node)
            invalidated_nodes << pure_node
          end
        end

        invalidated_nodes
      end

      def local_variable_name?(name)
        # Ruby constants start with Uppercase_Letter or Titlecase_Letter in the unicode property.
        # If name start with `@`, it is instance variable or class instance variable.
        # If name start with `$`, it is global variable.
        return false if name.start_with?(/[\p{Uppercase_Letter}\p{Titlecase_Letter}@$]/)
        return false if TypeConstruction::SPECIAL_LVAR_NAMES.include?(name)

        true
      end

      def local_variable_name!(name)
        local_variable_name?(name) || raise("#{name} is not a local variable")
      end

      def instance_variable_name?(name)
        name.start_with?(/@[^@]/)
      end

      def global_name?(name)
        name.start_with?('$')
      end

      def inspect
        s = "#<%s:%#018x " % [self.class, object_id]
        s << instance_variables.map(&:to_s).sort.map {|name| "#{name}=..." }.join(", ")
        s + ">"
      end
    end
  end
end
