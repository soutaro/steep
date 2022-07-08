module Steep
  module TypeInference
    class TypeEnv
      include NodeHelper

      attr_reader :local_variable_types
      attr_reader :instance_variable_types, :global_types, :constant_types
      attr_reader :constant_env
      attr_reader :pure_method_calls

      def to_s
        array = []

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
          array << "`#{node.loc.expression.source.lines[0]}`: #{type}"
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
              type
            end
          end
        end
      end

      def enforced_type(name)
        local_variable_types[name]&.[](1)
      end

      def assign_local_variables(assignments)
        local_variable_types = local_variable_types().dup
        invalidated_nodes = Set[]

        assignments.each do |name, new_type|
          local_variable_types[name] = [new_type, enforced_type(name)]
          invalidated_nodes.merge(invalidated_pure_nodes(::Parser::AST::Node.new(:lvar, [name])))
        end

        pure_calls = pure_method_calls().reject do |node, _|
          invalidated_nodes.include?(node)
        end

        update(
          local_variable_types: local_variable_types,
          pure_method_calls: pure_calls
        )
      end

      def assign_local_variable(name, var_type, enforced_type)
        local_variable_types = local_variable_types().dup
        local_variable_types[name] = [var_type, enforced_type]

        invalidated_nodes = invalidated_pure_nodes(::Parser::AST::Node.new(:lvar, [name]))
        pure_calls = pure_method_calls().reject {|node, _| invalidated_nodes.include?(node) }

        update(local_variable_types: local_variable_types, pure_method_calls: pure_calls)
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

      def join(env0, *envs)
        lvar_types = env0.local_variable_types.dup
        pure_calls = env0.pure_method_calls.dup

        envs.each do |env|
          lvar_names = Set[].merge(lvar_types.keys).merge(env.local_variable_types.keys)
          lvar_names.each do |name|
            _, original_enforced_type = local_variable_types[name]
            type1, _ = lvar_types[name]
            type2, _ = env.local_variable_types[name]

            type =
              case
              when type1 && type2
                AST::Types::Union.build(types: [type1, type2])
              when type1
                AST::Types::Union.build(types: [type1, AST::Builtin.nil_type])
              when type2
                AST::Types::Union.build(types: [type2, AST::Builtin.nil_type])
              else
                raise
              end

            lvar_types[name] = [type, original_enforced_type]
          end

          pure_nodes = Set[].merge(pure_calls.keys).merge(env.pure_method_calls.keys)
          pure_nodes.each do |node|
            call1, type1 = pure_calls[node]
            call2, type2 = env.pure_method_calls[node]

            call =
              case
              when call1 && call2
                # Assuming call1 and call2 are identical
                call1.with_return_type(
                  AST::Types::Union.build(types: [type1, type2])
                )
              when call1
                call1.with_return_type(
                  AST::Types::Union.build(types: [type1, AST::Builtin.nil_type])
                )
              when call2
                call2.with_return_type(
                  AST::Types::Union.build(types: [type2, AST::Builtin.nil_type])
                )
              else
                raise
              end

            pure_calls[node] = [call, call.return_type]
          end
        end

        update(local_variable_types: lvar_types, pure_method_calls: pure_calls)
      end

      def add_pure_call(node, call, type)
        if (c, _ = pure_method_calls[node]) && c == call
          return self
        end

        invalidated_nodes = invalidated_pure_nodes(node)
        pure_method_calls = self.pure_method_calls.reject do |node, _|
          invalidated_nodes.include?(node)
        end
        pure_method_calls[node] = [call, type]

        update(pure_method_calls: pure_method_calls)
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
        invalidated_nodes = invalidated_pure_nodes(node)

        pure_method_calls = self.pure_method_calls.reject do |node, _|
          invalidated_nodes.include?(node)
        end

        update(pure_method_calls: pure_method_calls)
      end

      def invalidated_pure_nodes(invalidated_node)
        invalidated_nodes = Set[]

        pure_method_calls.each_key do |pure_node|
          descendants = @pure_node_descendants[invalidated_node] ||= each_descendant_node(pure_node).to_set
          if descendants.member?(invalidated_node)
            invalidated_nodes << pure_node
          end
        end

        invalidated_nodes
      end

      def local_variable_name?(name)
        name.start_with?(/[a-z_]/)
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
