module Steep
  module Subtyping
    class Check
      attr_reader :factory
      attr_reader :cache
      attr_reader :assumptions

      def initialize(factory:)
        @factory = factory
        @cache = Cache.new()
      end

      def with_context(self_type:, instance_type:, class_type:, constraints:)
        @self_type = self_type
        @instance_type = instance_type
        @class_type = class_type
        @constraints = constraints
        @assumptions = Set[]

        yield
      ensure
        @self_type = nil
        @instance_type = nil
        @class_type = nil
        @constraints = nil
        @assumptions = nil
      end

      def push_assumption(relation)
        assumptions << relation
        yield
      ensure
        assumptions.delete(relation)
      end

      def self_type
        @self_type || raise
      end

      def instance_type
        @instance_type || raise
      end

      def class_type
        @class_type || raise
      end

      def constraints
        @constraints || raise
      end

      def each_ancestor(ancestors, &block)
        if block_given?
          if ancestors.super_class
            yield ancestors.super_class
          end
          ancestors.each_included_module(&block)
          ancestors.each_included_interface(&block)
          ancestors.each_prepended_module(&block)
          ancestors.each_extended_module(&block)
          ancestors.each_extended_interface(&block)
        else
          enum_for :each_ancestor, ancestors
        end
      end

      def instance_super_types(type_name, args:)
        ancestors = factory.definition_builder.ancestor_builder.one_instance_ancestors(type_name)

        subst = unless args.empty?
                  args_ = args.map {|type| factory.type_1(type) }
                  RBS::Substitution.build(ancestors.params, args_)
                end

        each_ancestor(ancestors).map do |ancestor|
          name = ancestor.name

          case ancestor
          when RBS::Definition::Ancestor::Instance
            args = ancestor.args.map do |type|
              type = type.sub(subst) if subst
              factory.type(type)
            end

            if ancestor.name.class?
              AST::Types::Name::Instance.new(
                name: name,
                args: args,
                location: nil
              )
            else
              AST::Types::Name::Interface.new(
                name: name,
                args: args,
                location: nil
              )
            end
          when RBS::Definition::Ancestor::Singleton
            AST::Types::Name::Singleton.new(
              name: name,
              location: nil
            )
          end
        end
      end

      def singleton_super_types(type_name)
        ancestors = factory.definition_builder.ancestor_builder.one_singleton_ancestors(type_name)

        ancestors.each_ancestor.map do |ancestor|
          name = ancestor.name

          case ancestor
          when RBS::Definition::Ancestor::Instance
            args = ancestor.args.map do |type|
              factory.type(type)
            end

            if ancestor.name.class?
              AST::Types::Name::Instance.new(
                name: name,
                args: args,
                location: nil
              )
            else
              AST::Types::Name::Interface.new(
                name: name,
                args: args,
                location: nil
              )
            end
          when RBS::Definition::Ancestor::Singleton
            AST::Types::Name::Singleton.new(
              name: name,
              location: nil
            )
          end
        end
      end

      def check(relation, constraints:, self_type:, instance_type:, class_type:)
        with_context(self_type: self_type, instance_type: instance_type, class_type: class_type, constraints: constraints) do
          check_type(relation)
        end
      end

      def check_type(relation)
        relation.type!

        Steep.logger.tagged "#{relation.sub_type} <: #{relation.super_type}" do
          cached = cache[relation, self_type, instance_type, class_type]
          if cached && constraints.empty?
            cached
          else
            if assumptions.member?(relation)
              success(relation)
            else
              push_assumption(relation) do
                check_type0(relation).tap do |result|
                  Steep.logger.debug "result=#{result.class}"
                  cache[relation, self_type, instance_type, class_type] = result if cacheable?(relation)
                end
              end
            end
          end
        end
      end

      def alias?(type)
        type.is_a?(AST::Types::Name::Alias)
      end

      def cacheable?(relation)
        relation.sub_type.free_variables.empty? && relation.super_type.free_variables.empty?
      end

      def true_type?(type)
        case type
        when AST::Types::Literal
          type.value == true
        else
          AST::Builtin::TrueClass.instance_type?(type)
        end
      end

      def false_type?(type)
        case type
        when AST::Types::Literal
          type.value == false
        else
          AST::Builtin::FalseClass.instance_type?(type)
        end
      end

      include Result::Helper

      def check_type0(relation)
        case
        when same_type?(relation)
          success(relation)

        when relation.sub_type.is_a?(AST::Types::Any) || relation.super_type.is_a?(AST::Types::Any)
          success(relation)

        when relation.super_type.is_a?(AST::Types::Void)
          success(relation)

        when relation.super_type.is_a?(AST::Types::Top)
          success(relation)

        when relation.sub_type.is_a?(AST::Types::Bot)
          success(relation)

        when relation.sub_type.is_a?(AST::Types::Logic::Base) && (true_type?(relation.super_type) || false_type?(relation.super_type))
          success(relation)

        when relation.super_type.is_a?(AST::Types::Boolean)
          Expand(relation) do
            check_type(
              Relation.new(
                sub_type: relation.sub_type,
                super_type: AST::Types::Union.build(types: [AST::Builtin.true_type, AST::Builtin.false_type])
              )
            )
          end

        when relation.sub_type.is_a?(AST::Types::Boolean)
          Expand(relation) do
            check_type(
              Relation.new(
                sub_type: AST::Types::Union.build(types: [AST::Builtin.true_type, AST::Builtin.false_type]),
                super_type: relation.super_type
              )
            )
          end

        when relation.sub_type.is_a?(AST::Types::Self) && !self_type.is_a?(AST::Types::Self)
          Expand(relation) do
            check_type(Relation.new(sub_type: self_type, super_type: relation.super_type))
          end

        when relation.sub_type.is_a?(AST::Types::Instance) && !instance_type.is_a?(AST::Types::Instance)
          Expand(relation) do
            check_type(Relation.new(sub_type: instance_type, super_type: relation.super_type))
          end

        when relation.super_type.is_a?(AST::Types::Instance) && !instance_type.is_a?(AST::Types::Instance)
          All(relation) do |result|
            rel = Relation.new(sub_type: relation.sub_type, super_type: instance_type)
            result.add(rel, rel.flip) do |r|
              check_type(r)
            end
          end.tap do
            Steep.logger.error { "`T <: instance` doesn't hold generally, but testing it with `#{relation} && #{relation.flip}` for compatibility"}
          end

        when relation.sub_type.is_a?(AST::Types::Class) && !instance_type.is_a?(AST::Types::Class)
          Expand(relation) do
            check_type(Relation.new(sub_type: class_type, super_type: relation.super_type))
          end

        when relation.super_type.is_a?(AST::Types::Class) && !instance_type.is_a?(AST::Types::Class)
          All(relation) do |result|
            rel = Relation.new(sub_type: relation.sub_type, super_type: class_type)
            result.add(rel, rel.flip) do |r|
              check_type(r)
            end
          end.tap do
            Steep.logger.error { "`T <: class` doesn't hold generally, but testing with `#{relation} && |- #{relation.flip}` for compatibility"}
          end

        when alias?(relation.sub_type)
          Expand(relation) do
            check_type(Relation.new(sub_type: expand_alias(relation.sub_type), super_type: relation.super_type))
          end

        when alias?(relation.super_type)
          Expand(relation) do
            check_type(Relation.new(super_type: expand_alias(relation.super_type), sub_type: relation.sub_type))
          end

        when relation.super_type.is_a?(AST::Types::Var) && constraints.unknown?(relation.super_type.name)
          constraints.add(relation.super_type.name, sub_type: relation.sub_type)
          Success(relation)

        when relation.sub_type.is_a?(AST::Types::Var) && constraints.unknown?(relation.sub_type.name)
          constraints.add(relation.sub_type.name, super_type: relation.super_type)
          Success(relation)

        when relation.sub_type.is_a?(AST::Types::Union)
          All(relation) do |result|
            relation.sub_type.types.each do |sub_type|
              rel = Relation.new(sub_type: sub_type, super_type: relation.super_type)
              result.add(rel) do
                check_type(rel)
              end
            end
          end

        when relation.super_type.is_a?(AST::Types::Union)
          Any(relation) do |result|
            relation.super_type.types.each do |super_type|
              rel = Relation.new(sub_type: relation.sub_type, super_type: super_type)
              result.add(rel) do
                check_type(rel)
              end
            end
          end

        when relation.sub_type.is_a?(AST::Types::Intersection)
          Any(relation) do |result|
            relation.sub_type.types.each do |sub_type|
              rel = Relation.new(sub_type: sub_type, super_type: relation.super_type)
              result.add(rel) do
                check_type(rel)
              end
            end
          end

        when relation.super_type.is_a?(AST::Types::Intersection)
          All(relation) do |result|
            relation.super_type.types.each do |super_type|
              result.add(Relation.new(sub_type: relation.sub_type, super_type: super_type)) do |rel|
                check_type(rel)
              end
            end
          end

        when relation.super_type.is_a?(AST::Types::Var) || relation.sub_type.is_a?(AST::Types::Var)
          Failure(relation, Result::Failure::UnknownPairError.new(relation: relation))

        when relation.super_type.is_a?(AST::Types::Name::Interface)
          Expand(relation) do
            check_interface(relation.map {|type| factory.interface(type, private: false) })
          end

        when relation.sub_type.is_a?(AST::Types::Name::Base) && relation.super_type.is_a?(AST::Types::Name::Base)
          if relation.sub_type.name == relation.super_type.name && relation.sub_type.class == relation.super_type.class
            if arg_type?(relation.sub_type) && arg_type?(relation.super_type)
              check_type_arg(relation)
            else
              Success(relation)
            end
          else
            possible_sub_types =
              case relation.sub_type
              when AST::Types::Name::Instance
                instance_super_types(relation.sub_type.name, args: relation.sub_type.args)
              when AST::Types::Name::Singleton
                singleton_super_types(relation.sub_type.name)
              else
                []
              end

            unless possible_sub_types.empty?
              Any(relation) do |result|
                possible_sub_types.each do |sub_type|
                  result.add(Relation.new(sub_type: sub_type, super_type: relation.super_type)) do |rel|
                    check_type(rel)
                  end
                end
              end
            else
              Failure(relation, Result::Failure::UnknownPairError.new(relation: relation))
            end
          end

        when relation.sub_type.is_a?(AST::Types::Proc) && relation.super_type.is_a?(AST::Types::Proc)
          name = :__proc__

          sub_type = relation.sub_type
          super_type = relation.super_type

          All(relation) do |result|
            result.add(relation.map {|p| p.type }) do |rel|
              check_function(name, rel)
            end

            result.add(relation.map {|p| p.block }) do |rel|
              check_block_given(name, rel) do
                Expand(rel.map {|b| b.type }) do |rel|
                  check_function(name, rel.flip)
                end
              end
            end
          end

        when relation.sub_type.is_a?(AST::Types::Tuple) && relation.super_type.is_a?(AST::Types::Tuple)
          if relation.sub_type.types.size >= relation.super_type.types.size
            pairs = relation.sub_type.types.take(relation.super_type.types.size).zip(relation.super_type.types)

            All(relation) do |result|
              pairs.each do |t1, t2|
                result.add(Relation.new(sub_type: t1, super_type: t2)) do |rel|
                  check_type(rel)
                end
              end
            end
          else
            Failure(relation, Result::Failure::UnknownPairError.new(relation: relation))
          end

        when relation.sub_type.is_a?(AST::Types::Tuple) && AST::Builtin::Array.instance_type?(relation.super_type)
          Expand(relation) do
            tuple_element_type =
              AST::Types::Union.build(
                types: relation.sub_type.types,
                location: relation.sub_type.location
              )

            check_type(Relation.new(sub_type: tuple_element_type, super_type: relation.super_type.args[0]))
          end

        when relation.sub_type.is_a?(AST::Types::Record) && relation.super_type.is_a?(AST::Types::Record)
          All(relation) do |result|
            relation.super_type.elements.each_key do |key|
              rel = Relation.new(
                sub_type: relation.sub_type.elements[key] || AST::Builtin.nil_type,
                super_type: relation.super_type.elements[key]
              )

              result.add(rel) do
                check_type(rel)
              end
            end
          end

        when relation.sub_type.is_a?(AST::Types::Record) && relation.super_type.is_a?(AST::Types::Name::Base)
          Expand(relation) do
            check_interface(relation.map {|type| factory.interface(type, private: false) })
          end

        when relation.super_type.is_a?(AST::Types::Literal)
          case
          when relation.super_type.value == true && AST::Builtin::TrueClass.instance_type?(relation.sub_type)
            Success(relation)
          when relation.super_type.value == false && AST::Builtin::FalseClass.instance_type?(relation.sub_type)
            Success(relation)
          else
            Failure(relation, Result::Failure::UnknownPairError.new(relation: relation))
          end

        when relation.super_type.is_a?(AST::Types::Nil) && AST::Builtin::NilClass.instance_type?(relation.sub_type)
          Success(relation)

        when relation.sub_type.is_a?(AST::Types::Nil) && AST::Builtin::NilClass.instance_type?(relation.super_type)
          Success(relation)

        when relation.sub_type.is_a?(AST::Types::Literal)
          Expand(relation) do
            check_type(Relation.new(sub_type: relation.sub_type.back_type, super_type: relation.super_type))
          end

        else
          Failure(relation, Result::Failure::UnknownPairError.new(relation: relation))
        end
      end

      def definition_for_type(type)
        type_name = type.name

        case type
        when AST::Types::Name::Instance
          factory.definition_builder.build_instance(type_name)
        when AST::Types::Name::Singleton
          factory.definition_builder.build_singleton(type_name)
        when AST::Types::Name::Interface
          factory.definition_builder.build_interface(type_name)
        else
          raise
        end
      end

      def arg_type?(type)
        case type
        when AST::Types::Name::Instance, AST::Types::Name::Interface
          type.args.size > 0
        else
          false
        end
      end

      def check_type_arg(relation)
        sub_args = relation.sub_type.args
        sup_args = relation.super_type.args

        sup_def = definition_for_type(relation.super_type)
        sup_params = sup_def.type_params_decl

        All(relation) do |result|
          sub_args.zip(sup_args, sup_params.each).each do |sub_arg, sup_arg, sup_param|
            case sup_param.variance
            when :covariant
              result.add(Relation.new(sub_type: sub_arg, super_type: sup_arg)) do |rel|
                check_type(rel)
              end
            when :contravariant
              result.add(Relation.new(sub_type: sup_arg, super_type: sub_arg)) do |rel|
                check_type(rel)
              end
            when :invariant
              rel = Relation.new(sub_type: sub_arg, super_type: sup_arg)
              result.add(rel, rel.flip) do |rel|
                check_type(rel)
              end
            end
          end
        end
      end

      def same_type?(relation)
        if assumptions.include?(relation) && assumptions.include?(relation.flip)
          return true
        end

        relation.sub_type == relation.super_type
      end

      def check_interface(relation)
        relation.interface!

        sub_interface, super_interface = relation

        method_pairs = super_interface.methods.each_with_object({}) do |(method_name, sup_method), hash|
          if sub_method = sub_interface.methods[method_name]
            hash[method_name] = Relation.new(sub_type: sub_method, super_type: sup_method)
          else
            return Failure(relation) { Result::Failure::MethodMissingError.new(name: method_name) }
          end
        end

        All(relation) do |result|
          method_pairs.each do |method_name, method_relation|
            result.add(relation) do
              check_method(method_name, method_relation)
            end
          end
        end
      end

      def check_method(name, relation)
        relation.method!

        sub_method, super_method = relation

        All(relation) do |all|
          super_method.method_types.each do |super_type|
            all.add(Relation.new(sub_type: sub_method, super_type: super_type)) do |rel|
              Any(rel) do |any|
                sub_method.method_types.each do |sub_type|
                  any.add(Relation.new(sub_type: sub_type, super_type: super_type)) do |rel|
                    check_generic_method_type(name, rel)
                  end
                end
              end
            end
          end
        end
      end

      def check_generic_method_type(name, relation)
        relation.method!

        sub_type, super_type = relation

        case
        when sub_type.type_params.empty? && super_type.type_params.empty?
          check_method_type(name, relation)

        when !sub_type.type_params.empty? && super_type.type_params.empty?
          # Check if super_type is an instance of sub_type.
          Expand(relation) do
            sub_args = sub_type.type_params.map {|x| AST::Types::Var.fresh(x) }
            sub_type_ = sub_type.instantiate(Interface::Substitution.build(sub_type.type_params, sub_args))

            constraints.add_var(*sub_args)

            rel = Relation.new(sub_type: sub_type_, super_type: super_type)

            match_method_type(name, rel) do |pairs|
              subst = pairs.each.with_object(Interface::Substitution.empty) do |(sub, sup), subst|
                case
                when sub.is_a?(AST::Types::Var) && sub_args.include?(sub)
                  if subst.key?(sub.name) && subst[sub.name] != sup
                    return Failure(rel, Result::Failure::PolyMethodSubtyping.new(name: name))
                  else
                    subst.add!(sub.name, sup)
                  end
                when sup.is_a?(AST::Types::Var) && sub_args.include?(sup)
                  if subst.key?(sup.name) && subst[sup.name] != sub
                    return Failure(rel, Result::Failure::PolyMethodSubtyping.new(name: name))
                  else
                    subst.add!(sup.name, sub)
                  end
                end
              end

              check_method_type(name, Relation.new(sub_type: sub_type_.subst(subst), super_type: super_type))
            end
          end

        when sub_type.type_params.empty? && !super_type.type_params.empty?
          # Check if sub_type is an instance of super_type && no constraints on type variables (any).
          Expand(relation) do
            match_method_type(name, relation) do
              sub_args = sub_type.type_params.map {|x| AST::Types::Var.fresh(x) }
              sub_type_ = sub_type.instantiate(Interface::Substitution.build(sub_type.type_params, sub_args))

              constraints.add_var(*sub_args)

              rel_ = Relation.new(sub_type: sub_type_, super_type: super_type)
              result = check_method_type(name, rel_)

              if result.success? && sub_args.map(&:name).none? {|var| constraints.has_constraint?(var) }
                result
              else
                Failure(rel_, Result::Failure::PolyMethodSubtyping.new(name: name))
              end
            end
          end

        when super_type.type_params.size == sub_type.type_params.size
          # Check if they have the same type arity
          Expand(relation) do
            args = sub_type.type_params.map {|x| AST::Types::Var.fresh(x) }

            sub_type_ = sub_type.instantiate(Interface::Substitution.build(sub_type.type_params, args))
            super_type_ = super_type.instantiate(Interface::Substitution.build(super_type.type_params, args))

            constraints.add_var(*args)

            check_method_type(name, Relation.new(sub_type: sub_type_, super_type: super_type_))
          end

        else
          Failure(relation, Result::Failure::PolyMethodSubtyping.new(name: name))
        end
      end

      def check_method_type(name, relation)
        relation.method!

        sub_type, super_type = relation

        All(relation) do |result|
          result.add(Relation.new(sub_type: sub_type.type, super_type: super_type.type)) do |rel|
            check_function(name, rel)
          end

          result.add(Relation.new(sub_type: sub_type.block, super_type: super_type.block)) do |rel|
            check_block_given(name, rel) do
              Expand(Relation.new(sub_type: super_type.block.type, super_type: sub_type.block.type)) do |rel|
                check_function(name, rel)
              end
            end
          end
        end
      end

      def check_block_given(name, relation, &block)
        relation.block!

        sub_block, super_block = relation

        case
        when !super_block && !sub_block
          Success(relation)
        when super_block && sub_block && super_block.optional? == sub_block.optional?
          Expand(relation, &block)
        when sub_block&.optional?
          Success(relation)
        else
          Failure(relation, Result::Failure::BlockMismatchError.new(name: name))
        end
      end

      def check_function(name, relation)
        relation.function!

        All(relation) do |result|
          result.add(relation.map {|fun| fun.params }) do |rel|
            check_method_params(name, rel)
          end

          result.add(relation.map {|fun| fun.return_type }) do |rel|
            check_type(rel)
          end
        end
      end

      def check_method_params(name, relation)
        relation.params!
        pairs = match_params(name, relation)

        case pairs
        when Array
          unless pairs.empty?
            All(relation) do |result|
              pairs.each do |(sub_type, super_type)|
                result.add(Relation.new(sub_type: super_type, super_type: sub_type)) do |rel|
                  check_type(rel)
                end
              end

              result
            end
          else
            Success(relation)
          end
        else
          pairs
        end
      end

      def match_method_type(name, relation)
        relation.method!

        sub_type, super_type = relation

        pairs = []

        match_params(name, relation.map {|m| m.type.params }).tap do |param_pairs|
          return param_pairs unless param_pairs.is_a?(Array)

          pairs.push(*param_pairs)
          pairs.push [sub_type.type.return_type, super_type.type.return_type]
        end

        check_block_given(name, relation.map {|m| m.block }) do |rel|
          match_params(name, rel.map {|m| m.type.params }).tap do |param_pairs|
            return param_pairs unless param_pairs.is_a?(Array)

            pairs.push(*param_pairs)
            pairs.push [sub_type.type.return_type, super_type.type.return_type]
          end
        end

        if block_given?
          yield pairs
        else
          pairs
        end
      end

      def match_params(name, relation)
        relation.params!

        sub_params, super_params = relation

        pairs = []

        sub_flat = sub_params.flat_unnamed_params
        sup_flat = super_params.flat_unnamed_params

        failure = Failure(relation, Result::Failure::ParameterMismatchError.new(name: name))

        case
        when super_params.rest
          return failure unless sub_params.rest

          while sub_flat.size > 0
            sub_type = sub_flat.shift
            sup_type = sup_flat.shift

            if sup_type
              pairs << [sub_type.last, sup_type.last]
            else
              pairs << [sub_type.last, super_params.rest]
            end
          end

          if sub_params.rest
            pairs << [sub_params.rest, super_params.rest]
          end

        when sub_params.rest
          while sub_flat.size > 0
            sub_type = sub_flat.shift
            sup_type = sup_flat.shift

            if sup_type
              pairs << [sub_type.last, sup_type.last]
            else
              break
            end
          end

          if sub_params.rest && !sup_flat.empty?
            sup_flat.each do |sup_type|
              pairs << [sub_params.rest, sup_type.last]
            end
          end
        when sub_params.required.size + sub_params.optional.size >= super_params.required.size + super_params.optional.size
          while sub_flat.size > 0
            sub_type = sub_flat.shift
            sup_type = sup_flat.shift

            if sup_type
              pairs << [sub_type.last, sup_type.last]
            else
              if sub_type.first == :required
                return failure
              else
                break
              end
            end
          end
        else
          return failure
        end

        sub_flat_kws = sub_params.flat_keywords
        sup_flat_kws = super_params.flat_keywords

        sup_flat_kws.each do |name, _|
          if sub_flat_kws.key?(name)
            pairs << [sub_flat_kws[name], sup_flat_kws[name]]
          else
            if sub_params.rest_keywords
              pairs << [sub_params.rest_keywords, sup_flat_kws[name]]
            else
              return failure
            end
          end
        end

        sub_params.required_keywords.each do |name, _|
          unless super_params.required_keywords.key?(name)
            return failure
          end
        end

        if sub_params.rest_keywords && super_params.rest_keywords
          pairs << [sub_params.rest_keywords, super_params.rest_keywords]
        end

        pairs
      end

      def expand_alias(type, &block)
        factory.expand_alias(type, &block)
      end
    end
  end
end
