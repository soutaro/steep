module Steep
  module Subtyping
    class Check
      attr_reader :builder
      attr_reader :cache

      def initialize(builder:)
        @builder = builder
        @cache = Cache.new()
        @bounds = []
      end

      def factory
        builder.factory
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

      def push_variable_bounds(params)
        case params
        when Array
          b = params.each.with_object({}) do |param, hash|
            hash[param.name] = param.upper_bound
          end
        when Hash
          b = params
        end

        @bounds.push(b)
        yield

      ensure
        @bounds.pop
      end

      def variable_upper_bound(name)
        @bounds.reverse_each do |hash|
          if hash.key?(name)
            return hash[name]
          end
        end

        nil
      end

      def variable_upper_bounds
        @bounds.each_with_object({}) do |bounds, hash|
          hash.merge!(bounds)
        end
      end

      def assumptions
        @assumptions || raise
      end

      def self_type
        @self_type || raise
      end

      def instance_type
        @instance_type || AST::Types::Instance.instance
      end

      def class_type
        @class_type || AST::Types::Class.instance
      end

      def constraints
        @constraints || raise
      end

      def each_ancestor(ancestors, &block)
        if block
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
                  params = ancestors.params or raise
                  RBS::Substitution.build(params, args_)
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
          bounds = cache_bounds(relation)
          fvs = relation.sub_type.free_variables + relation.super_type.free_variables
          cached = cache[relation, @self_type, @instance_type, @class_type, bounds]
          if cached && fvs.none? {|var| var.is_a?(Symbol) && constraints.unknown?(var) }
            cached
          else
            if assumptions.member?(relation)
              success(relation)
            else
              push_assumption(relation) do
                check_type0(relation).tap do |result|
                  Steep.logger.debug "result=#{result.class}"
                  cache[relation, @self_type, @instance_type, @class_type, bounds] = result
                end
              end
            end
          end
        end
      end

      def cache_bounds(relation)
        vars = relation.sub_type.free_variables + relation.super_type.free_variables
        vars.each.with_object({}) do |var, hash| #$ Hash[Symbol, AST::Types::t]
          next unless var.is_a?(Symbol)
          if upper_bound = variable_upper_bound(var)
            hash[var] = upper_bound
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
          AST::Builtin::TrueClass.instance_type?(type) ? true : false
        end
      end

      def false_type?(type)
        case type
        when AST::Types::Literal
          type.value == false
        else
          AST::Builtin::FalseClass.instance_type?(type) ? true : false
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
          if ub = variable_upper_bound(relation.super_type.name)
            Expand(relation) do
              check_type(Relation.new(sub_type: relation.sub_type, super_type: ub))
            end.tap do |result|
              if result.success?
                constraints.add(relation.super_type.name, sub_type: relation.sub_type)
              end
            end
          else
            constraints.add(relation.super_type.name, sub_type: relation.sub_type)
            Success(relation)
          end

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
            relation.super_type.types.sort_by {|ty| (path = hole_path(ty)) ? -path.size : -Float::INFINITY }.each do |super_type|
              rel = Relation.new(sub_type: relation.sub_type, super_type: super_type)
              result.add(rel) do
                check_type(rel)
              end
            end
          end

        when relation.sub_type.is_a?(AST::Types::Intersection)
          Any(relation) do |result|
            relation.sub_type.types.sort_by {|ty| (path = hole_path(ty)) ? -path.size : -Float::INFINITY }.each do |sub_type|
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

        when relation.sub_type.is_a?(AST::Types::Var) && ub = variable_upper_bound(relation.sub_type.name)
          Expand(relation) do
            check_type(Relation.new(sub_type: ub, super_type: relation.super_type))
          end

        when relation.super_type.is_a?(AST::Types::Var) || relation.sub_type.is_a?(AST::Types::Var)
          Failure(relation, Result::Failure::UnknownPairError.new(relation: relation))

        when relation.super_type.is_a?(AST::Types::Name::Interface)
          Expand(relation) do
            check_interface(
              relation.map {|type|
                builder.shape(
                  type,
                  public_only: true,
                  config: Interface::Builder::Config.new(
                    self_type: type,
                    instance_type: instance_type,
                    class_type: class_type,
                    variable_bounds: variable_upper_bounds
                  )
                ) or return Failure(relation, Result::Failure::UnknownPairError.new(relation: relation))
              }
            )
          end

        when relation.sub_type.is_a?(AST::Types::Name::Base) && relation.super_type.is_a?(AST::Types::Name::Base)
          if relation.sub_type.name == relation.super_type.name && relation.sub_type.class == relation.super_type.class
            if arg_type?(relation.sub_type) && arg_type?(relation.super_type)
              check_type_arg(_ = relation)
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
                [] #: Array[super_type]
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
          yield_self do
            name = :__proc__

            sub_type = relation.sub_type
            super_type = relation.super_type

            All(relation) do |result|
              result.add(Relation(sub_type.type, super_type.type)) do |rel|
                check_function(name, rel)
              end

              result.add_result check_self_type_binding(relation, sub_type.self_type, super_type.self_type)

              result.add(Relation(sub_type.block, super_type.block)) do |rel|
                case ret = expand_block_given(name, rel)
                when Relation
                  All(ret) do |result|
                    result.add_result check_self_type_binding(ret, ret.super_type.self_type, ret.sub_type.self_type)
                    result.add(ret.map {|b| b.type }) {|r| check_function(name, r.flip) }
                  end
                when Result::Base
                  ret
                when true
                  nil
                end
              end
            end
          end

        when relation.sub_type.is_a?(AST::Types::Tuple) && relation.super_type.is_a?(AST::Types::Tuple)
          if relation.sub_type.types.size >= relation.super_type.types.size
            pairs = relation.sub_type.types.take(relation.super_type.types.size).zip(relation.super_type.types)

            All(relation) do |result|
              pairs.each do |t1, t2|
                t2 or raise
                result.add(Relation.new(sub_type: t1, super_type: t2)) do |rel|
                  check_type(rel)
                end
              end
            end
          else
            Failure(relation, Result::Failure::UnknownPairError.new(relation: relation))
          end

        when relation.sub_type.is_a?(AST::Types::Tuple) && (super_type = AST::Builtin::Array.instance_type?(relation.super_type))
          Expand(relation) do
            tuple_element_type =
              AST::Types::Union.build(
                types: relation.sub_type.types,
                location: relation.sub_type.location
              )

            check_type(Relation.new(sub_type: tuple_element_type, super_type: super_type.args[0]))
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
            check_interface(
              relation.map {|type|
                builder.shape(
                  type,
                  public_only: true,
                  config: Interface::Builder::Config.new(
                    self_type: type,
                    instance_type: instance_type,
                    class_type: class_type,
                    variable_bounds: variable_upper_bounds
                  )
                ) or raise
              }
            )
          end

        when relation.sub_type.is_a?(AST::Types::Proc) && AST::Builtin::Proc.instance_type?(relation.super_type)
          Success(relation)

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
          # NilClass <: nil
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
        case type
        when AST::Types::Name::Instance
          factory.definition_builder.build_instance(type.name)
        when AST::Types::Name::Singleton
          factory.definition_builder.build_singleton(type.name)
        when AST::Types::Name::Interface
          factory.definition_builder.build_interface(type.name)
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

        builder.factory.normalize_type(relation.sub_type) == builder.factory.normalize_type(relation.super_type)
      end

      def check_interface(relation)
        relation.interface!

        sub_interface, super_interface = relation

        method_pairs = super_interface.methods.each_with_object({}) do |(method_name, sup_method), hash| #$ Hash[Symbol, Relation[Interface::Shape::Entry]]
          if sub_method = sub_interface.methods[method_name]
            hash[method_name] = Relation.new(sub_type: sub_method, super_type: sup_method)
          else
            return Failure(relation) { Result::Failure::MethodMissingError.new(name: method_name) }
          end
        end

        All(relation) do |result|
          method_pairs.each do |method_name, method_relation|
            result.add(method_relation) do
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
            sub_args = sub_type.type_params.map {|param| AST::Types::Var.fresh(param.name) }
            sub_type_ = sub_type.instantiate(Interface::Substitution.build(sub_type.type_params.map(&:name), sub_args))

            sub_args.each do |s|
              constraints.unknown!(s.name)
            end

            relation = Relation.new(sub_type: sub_type_, super_type: super_type)
            All(relation) do |result|
              sub_args.zip(sub_type.type_params).each do |arg, param|
                param or raise

                if ub = param.upper_bound
                  result.add(Relation.new(sub_type: arg, super_type: ub)) do |rel|
                    check_type(rel)
                  end
                end
              end

              if failure = match_method_type_fails?(name, sub_type_, super_type)
                result.add_result(failure)
              else
                result.add_result(check_method_type(name, Relation(sub_type_, super_type)))
              end

              result.add(relation) do |rel|
                check_constraints(
                  relation,
                  variables: sub_args.map(&:name),
                  variance: VariableVariance.from_method_type(sub_type_)
                )
              end
            end
          end

        when sub_type.type_params.empty? && !super_type.type_params.empty?
          # Check if sub_type is an instance of super_type && no constraints on type variables (any).
          All(relation) do |result|
            super_args = super_type.type_params.map {|param| AST::Types::Var.fresh(param.name) }
            super_type_ = super_type.instantiate(Interface::Substitution.build(super_type.type_params.map(&:name), super_args))

            if failure = match_method_type_fails?(name, sub_type, super_type_)
              result.add_result(failure)
            else
              super_args.each do |arg|
                constraints.unknown!(arg.name)
              end

              result.add(Relation(sub_type, super_type_)) do |rel_|
                ret = check_method_type(name, rel_)

                if ret.success? && super_args.map(&:name).none? {|var| constraints.has_constraint?(var) }
                  ret
                else
                  Failure(rel_, Result::Failure::PolyMethodSubtyping.new(name: name))
                end
              end
            end
          end

        when super_type.type_params.size == sub_type.type_params.size
          # If they have the same arity, run the normal F-sub subtyping checking.
          All(relation) do |result|
            args = sub_type.type_params.map {|type_param| AST::Types::Var.fresh(type_param.name) }
            args.each {|arg| constraints.unknown!(arg.name) }

            upper_bounds = {} #: Hash[Symbol, AST::Types::t]
            relations = [] #: Array[Relation[AST::Types::t]]

            args.zip(sub_type.type_params, super_type.type_params).each do |arg, sub_param, sup_param|
              # @type var arg: AST::Types::Var
              # @type var sub_param: Interface::TypeParam?
              # @type var super_param: Interface::TypeParam?

              sub_param or raise
              sup_param or raise

              sub_ub = sub_param.upper_bound
              sup_ub = sup_param.upper_bound

              case
              when sub_ub && sup_ub
                upper_bounds[arg.name] = sub_ub
                relations << Relation.new(sub_type: sub_ub, super_type: sup_ub)
              when sub_ub && !sup_ub
                upper_bounds[arg.name] = sub_ub
              when !sub_ub && sup_ub
                result.add(Relation.new(sub_type: AST::Types::Var.new(name: sub_param.name), super_type: sub_ub)) do |rel|
                  Failure(rel, Result::Failure::PolyMethodSubtyping.new(name: name))
                end
              when !sub_ub && !sup_ub
                # no constraints
              end
            end

            push_variable_bounds(upper_bounds) do
              sub_type_ = sub_type.instantiate(Interface::Substitution.build(sub_type.type_params.map(&:name), args))
              super_type_ = super_type.instantiate(Interface::Substitution.build(super_type.type_params.map(&:name), args))

              result.add(*relations) {|rel| check_type(rel) }
              result.add(Relation.new(sub_type: sub_type_, super_type: super_type_)) do |rel|
                check_method_type(name, rel)
              end
            end
          end

        else
          Failure(relation, Result::Failure::PolyMethodSubtyping.new(name: name))
        end
      end

      def check_constraints(relation, variables:, variance:)
        checker = Check.new(builder: builder)

        constraints.solution(
          checker,
          variance: variance,
          variables: variables,
          self_type: self_type,
          instance_type: instance_type,
          class_type: class_type
        )

        Success(relation)
      rescue Constraints::UnsatisfiableConstraint => error
        Failure(relation, Result::Failure::UnsatisfiedConstraints.new(error))
      end

      def check_method_type(name, relation)
        relation.method!

        sub_type, super_type = relation

        sub_type.type_params.empty? or raise "Expected monomorphic method type: #{sub_type}"
        super_type.type_params.empty? or raise "Expected monomorphic method type: #{super_type}"

        All(relation) do |result|
          type_relation = Relation.new(sub_type: sub_type.type, super_type: super_type.type)

          ret = expand_block_given(name, Relation.new(sub_type: sub_type.block, super_type: super_type.block))

          case ret
          when true
            result.add(type_relation) { check_function(name, type_relation) }
          when Relation
            result.add(type_relation) { check_function(name, type_relation) }
            result.add(ret) do
              All(ret) do |result|
                result.add_result(check_self_type_binding(ret, ret.super_type.self_type, ret.sub_type.self_type))
                result.add(Relation(ret.super_type.type, ret.sub_type.type)) do |block_relation|
                  check_function(name, block_relation)
                end
              end
            end
          when Result::Failure
            result.add(ret.relation) { ret }
          end
        end
      end

      def expand_block_given(name, relation, &block)
        relation.block!

        sub_block, super_block = relation

        case
        when !super_block && !sub_block
          true
        when super_block && sub_block && super_block.optional? == sub_block.optional?
          Relation.new(sub_type: sub_block, super_type: super_block)
        when sub_block&.optional?
          true
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

      def check_self_type_binding(relation, sub_self, super_self)
        case
        when sub_self.nil? && super_self.nil?
          nil
        when sub_self && super_self
          # ^() [self: T] -> void <: ^() [self: S] -> void                              ==> S <: T
          # () { () [self: S] -> void } -> void <: () { () [self: T] -> void } -> void  ==> S <: T
          check_type(Relation(super_self, sub_self))
        when sub_self.is_a?(AST::Types::Top) && super_self.nil?
          # ^() [self: top] -> void <: ^() -> void                              ==> OK
          # () { () -> void } -> void <: () { () [self: top] -> void } -> void  ==> OK
          nil
        else
          Failure(relation, Result::Failure::SelfBindingMismatch.new)
        end
      end

      def check_method_params(name, relation)
        relation.params!
        pairs = match_params(name, relation)

        case pairs
        when Array
          unless pairs.empty?
            All(relation) do |result|
              pairs.each do |sub_type, super_type|
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

      def Relation(sub, sup)
        Relation.new(sub_type: sub, super_type: sup)
      end

      def match_method_type_fails?(name, type1, type2)
        match_params(name, Relation(type1.type.params, type2.type.params)).tap do |param_pairs|
          return param_pairs unless param_pairs.is_a?(Array)
        end

        case result = expand_block_given(name, Relation(type1.block, type2.block))
        when Result::Base
          return result
        when Relation
          match_params(name, result.map {|m| m.type.params }).tap do |param_pairs|
            return param_pairs unless param_pairs.is_a?(Array)
          end
        end

        nil
      end

      def match_params(name, relation)
        relation.params!

        sub_params, super_params = relation

        pairs = [] #: Array[[AST::Types::t, AST::Types::t]]

        sub_flat = sub_params.flat_unnamed_params
        sup_flat = super_params.flat_unnamed_params

        failure = Failure(relation, Result::Failure::ParameterMismatchError.new(name: name))

        case
        when super_params.rest
          return failure unless sub_params.rest

          while sub_flat.size > 0
            sub_type = sub_flat.shift or raise
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
            sub_type = sub_flat.shift or raise
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
            sub_type = sub_flat.shift or raise
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

      # Returns the shortest type paths for one of the _unknown_ type variables.
      # Returns nil if there is no path.
      def hole_path(type, path = [])
        case type
        when AST::Types::Var
          if constraints.unknown?(type.name)
            [type]
          else
            nil
          end
        else
          paths = type.each_child.map do |ty|
            hole_path(ty, path)&.unshift(ty)
          end
          paths.compact.min_by(&:size)
        end
      end
    end
  end
end
