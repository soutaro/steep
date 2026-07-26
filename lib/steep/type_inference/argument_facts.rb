module Steep
  module TypeInference
    # Consumer side of the argument-sensitive entry facts (peça 3).
    #
    # The Runner records, per `(class#method, parameter, literal)`, the const facts that hold
    # at entry for exactly the callers that passed that literal. A branch guarded by a test of
    # that parameter against that literal is reachable only for those callers, so the branch
    # may assume the partition's facts.
    #
    # Two branch shapes express the same correlation, and both go through here:
    #
    #     case which            |    if which == :name
    #     when :name then ...   |      ...
    #                           |    elsif which == :age
    #                           |      ...
    #
    # Everything is keyed by `Postconditions::LiteralKey`, the same canonical literal string
    # the producer used, so the two sides agree by construction.
    module ArgumentFacts
      # `{ literal_key => { consts: { path => AST type }, ivars: { :@x => AST type } } }` —
      # the partitions recorded for `param_name` on the method currently being checked, or
      # `{}`.
      #
      # Returns `{}` when the parameter is reassigned anywhere in the method body: the
      # correlation is between the CALLER's argument and the branch, and once the local no
      # longer holds the value the caller passed, testing it proves nothing about the caller.
      def self.partitions_for(constr, param_name)
        method_context = constr.method_context or return {}
        return {} if method_context.reassigned_parameter?(param_name)

        class_name = constr.module_context&.class_name or return {}
        method_name = method_context.name or return {}

        partitions = constr.postconditions.lookup_argument_entry_facts(class_name.to_s, method_name)
        return {} if partitions.empty?

        factory = constr.checker.factory
        partitions.each_with_object({}) do |partition, result|
          next unless partition[:param_name] == param_name

          consts = to_ast_types(partition[:consts], factory)
          ivars = to_ast_types(partition[:ivars] || {}, factory)
          next if consts.empty? && ivars.empty?

          result[partition[:pattern]] = { consts: consts, ivars: ivars }
        end
      end

      def self.to_ast_types(rbs_types, factory)
        rbs_types.each_with_object({}) do |(key, rbs_type), acc|
          type = factory.type(rbs_type) rescue next
          acc[key] = type
        end
      end

      # `[param_name, literal_key]` when `node` is an equality test of a local against a
      # literal — `which == :name` or `:name == which` — else nil.
      #
      # Only `==` is recognized. `equal?`/`eql?` are deliberately left out: they are rare in
      # this position and carry different semantics.
      def self.literal_equality(node)
        return nil unless node.is_a?(Parser::AST::Node) && node.type == :send

        receiver, mname, *args = node.children
        return nil unless mname == :== && args.size == 1
        arg = args[0]

        if receiver.is_a?(Parser::AST::Node) && receiver.type == :lvar
          if (key = Postconditions::LiteralKey.of(arg))
            return [receiver.children[0], key]
          end
        end

        if arg.is_a?(Parser::AST::Node) && arg.type == :lvar
          if (key = Postconditions::LiteralKey.of(receiver))
            return [arg.children[0], key]
          end
        end

        nil
      end

      # The union of the facts of every partition whose literal is among `literal_keys` (a
      # `when` clause may list several patterns).
      def self.facts_for(partitions, literal_keys)
        consts = {} #: Hash[String, AST::Types::t]
        ivars = {} #: Hash[Symbol, AST::Types::t]

        literal_keys.each do |key|
          next unless (facts = partitions[key])
          consts.merge!(facts[:consts])
          ivars.merge!(facts[:ivars])
        end

        { consts: consts, ivars: ivars }
      end

      # Merge a partition's facts into a branch's env: consts through the same slot a
      # method-entry const fact uses, ivars as a refinement of the declared ivar type — so a
      # read inside the branch narrows exactly as it would if the fact had been proven
      # unconditionally at entry.
      def self.apply(constr, facts)
        consts = facts[:consts]
        ivars = facts[:ivars]
        return constr if consts.empty? && ivars.empty?

        constr.update_type_env do |env|
          env = env.with_method_entry_facts(self_methods: {}, consts: consts) unless consts.empty?
          env = env.refine_types(instance_variable_types: ivars) unless ivars.empty?
          env
        end
      end

      # Apply to `constr` the partitions selected by an `if <param> == <literal>` condition.
      # Used for the truthy branch only: the falsy branch means "not this literal", which
      # pins the argument to nothing.
      def self.apply_for_condition(constr, cond_node)
        param_name, key = literal_equality(cond_node)
        return constr unless param_name

        partitions = partitions_for(constr, param_name)
        return constr if partitions.empty?

        apply(constr, facts_for(partitions, [key]))
      end

      # The parameter names a def reassigns anywhere in its body (`which = :name`), including
      # inside nested blocks/conditionals. Computed once per method at `for_new_method` time
      # and cached on the MethodContext.
      def self.reassigned_parameters(def_node)
        return Set.new unless def_node.is_a?(Parser::AST::Node)

        body = def_node.type == :defs ? def_node.children[3] : def_node.children[2]
        return Set.new unless body

        names = Set.new #: Set[Symbol]
        collect_lvasgn(body, names)
        names
      end

      def self.collect_lvasgn(node, names)
        return unless node.is_a?(Parser::AST::Node)

        case node.type
        when :lvasgn, :op_asgn, :or_asgn, :and_asgn
          target = node.children[0]
          if node.type == :lvasgn
            names << target if target.is_a?(Symbol)
          elsif target.is_a?(Parser::AST::Node) && target.type == :lvasgn
            names << target.children[0]
          end
        when :argument, :arg, :optarg
          # Not an assignment to an existing local.
        end

        node.children.each { |child| collect_lvasgn(child, names) if child.is_a?(Parser::AST::Node) }
      end
    end
  end
end
