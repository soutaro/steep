module Steep
  module TypeInference
    class LocalVariableTypeEnv
      class Entry
        attr_reader :type
        attr_reader :annotations
        attr_reader :nodes

        def initialize(type:, annotations: [], nodes: [])
          @type = type
          @annotations = Set.new(annotations)
          @nodes = Set[].compare_by_identity.merge(nodes)
        end

        def update(type: self.type, annotations: self.annotations, nodes: self.nodes)
          Entry.new(type: type, annotations: annotations, nodes: nodes)
        end

        def ==(other)
          other.is_a?(Entry) &&
            other.type == type &&
            other.annotations == annotations &&
            other.nodes == nodes
        end

        def +(other)
          self.class.new(type: AST::Types::Union.build(types: [type, other.type]),
                         annotations: annotations + other.annotations,
                         nodes: nodes + other.nodes)
        end

        def optional
          self.class.new(type: AST::Types::Union.build(types: [type, AST::Builtin.nil_type]),
                         annotations: annotations,
                         nodes: nodes)
        end
      end

      attr_reader :subtyping
      attr_reader :self_type
      attr_reader :instance_type
      attr_reader :class_type
      attr_reader :declared_types
      attr_reader :assigned_types

      def self.empty(subtyping:, self_type:, instance_type:, class_type:)
        new(
          subtyping: subtyping,
          declared_types: {},
          assigned_types: {},
          self_type: self_type,
          instance_type: instance_type,
          class_type: class_type
        )
      end

      def initialize(subtyping:, declared_types:, assigned_types:, self_type:, instance_type:, class_type:)
        @subtyping = subtyping
        @self_type = self_type

        @declared_types = declared_types
        @assigned_types = assigned_types
        @class_type = class_type
        @instance_type = instance_type

        unless (intersection = Set.new(declared_types.keys) & Set.new(assigned_types.keys)).empty?
          raise "Declared types and assigned types should be disjoint: #{intersection}"
        end
      end

      def update(declared_types: self.declared_types, assigned_types: self.assigned_types, self_type: self.self_type, instance_type: self.instance_type, class_type: self.class_type)
        self.class.new(
          subtyping: subtyping,
          declared_types: declared_types,
          assigned_types: assigned_types,
          self_type: self_type,
          instance_type: instance_type,
          class_type: class_type
        )
      end

      def assign!(var, node:, type:)
        declared_type = declared_types[var]&.type

        if declared_type
          relation = Subtyping::Relation.new(sub_type: type, super_type: declared_type)
          constraints = Subtyping::Constraints.new(unknowns: Set.new)
          subtyping.check(relation, constraints: constraints, self_type: self_type, instance_type: instance_type, class_type: class_type).else do |result|
            yield declared_type, type, result if block_given?
          end
        end

        assignments = { var => Entry.new(type: type, nodes: [node]) }
        update(assigned_types: assigned_types.merge(assignments),
               declared_types: declared_types.reject {|k, _| k == var })
      end

      def assign(var, node:, type:)
        declared_type = declared_types[var]&.type

        if declared_type
          relation = Subtyping::Relation.new(sub_type: type, super_type: declared_type)
          constraints = Subtyping::Constraints.new(unknowns: Set.new)
          subtyping.check(relation, constraints: constraints, self_type: self_type, instance_type: instance_type, class_type: class_type).else do |result|
            yield declared_type, type, result
          end

          self
        else
          assignments = { var => Entry.new(type: type, nodes: [node]) }
          update(assigned_types: assigned_types.merge(assignments))
        end
      end

      def annotate(collection)
        decls = collection.var_type_annotations.each.with_object({}) do |(var, annotation), hash|
          type = collection.var_type(lvar: var)
          hash[var] = Entry.new(type: type, annotations: [annotation])
        end

        decls.each do |var, annot|
          inner_type = annot.type
          outer_type = self[var]

          if outer_type
            relation = Subtyping::Relation.new(sub_type: inner_type, super_type: outer_type)
            constraints = Subtyping::Constraints.new(unknowns: Set.new)
            subtyping.check(relation, constraints: constraints, self_type: self_type, instance_type: instance_type, class_type: class_type).else do |result|
              if block_given?
                yield var, outer_type, inner_type, result
              end
            end
          end
        end

        new_decls = declared_types.merge(decls)
        new_assigns = assigned_types.reject {|var, _| new_decls.key?(var) }

        update(declared_types: new_decls, assigned_types: new_assigns)
      end

      def [](var)
        entry(var)&.type
      end

      def entry(var)
        declared_types[var] || assigned_types[var]
      end

      def pin_assignments
        update(
          declared_types: assigned_types.merge(declared_types),
          assigned_types: {}
        )
      end

      def except(variables)
        update(
          declared_types: declared_types.reject {|var, _| variables.include?(var) },
          assigned_types: assigned_types.reject {|var, _| variables.include?(var) }
        )
      end

      def subst(s)
        update(
          declared_types: declared_types.transform_values {|e| e.update(type: e.type.subst(s)) },
          assigned_types: assigned_types.transform_values {|e| e.update(type: e.type.subst(s)) }
        )
      end

      def each
        if block_given?
          vars.each do |var|
            yield var, self[var]
          end
        else
          enum_for :each
        end
      end

      def vars
        @vars ||= Set.new(declared_types.keys + assigned_types.keys)
      end

      def join(*envs)
        if envs.empty?
          self
        else
          env = envs.inject do |env1, env2|
            assigned_types = {}
            declared_types = {}

            (env1.vars + env2.vars).each do |var|
              e1 = env1.entry(var)
              e2 = env2.entry(var)
              je = join_entry(e1, e2)

              if env1.declared_types.key?(var) || env2.declared_types.key?(var)
                declared_types[var] = je
              else
                assigned_types[var] = je
              end
            end

            LocalVariableTypeEnv.new(
              subtyping: subtyping,
              self_type: self_type,
              declared_types: declared_types,
              assigned_types: assigned_types,
              instance_type: instance_type,
              class_type: class_type
            )
          end

          decls = env.declared_types.merge(declared_types)
          assignments = env.assigned_types.reject {|var, _| decls.key?(var) }

          update(
            declared_types: decls,
            assigned_types: assignments,
          )
        end
      end

      def join_entry(e1, e2)
        case
        when e1 && e2
          e1 + e2
        when e1
          e1.optional
        when e2
          e2.optional
        else
          raise
        end
      end

      def to_s
        ss = []

        vars.each do |var|
          ss << "#{var}: #{self[var].to_s}"
        end

        "{#{ss.join(", ")}}"
      end
    end
  end
end
