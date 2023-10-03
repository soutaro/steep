module Steep
  module Signature
    class Validator
      Location = RBS::Location
      Declarations = RBS::AST::Declarations

      attr_reader :checker

      def initialize(checker:)
        @checker = checker
        @errors = []
      end

      def has_error?
        !no_error?
      end

      def no_error?
        @errors.empty?
      end

      def each_error(&block)
        if block
          @errors.each(&block)
        else
          enum_for :each_error
        end
      end

      def env
        checker.factory.env
      end

      def builder
        checker.factory.definition_builder
      end

      def type_name_resolver
        @type_name_resolver ||= RBS::Resolver::TypeNameResolver.new(env)
      end

      def validator
        @validator ||= RBS::Validator.new(env: env, resolver: type_name_resolver)
      end

      def factory
        checker.factory
      end

      def validate
        @errors = []

        validate_decl
        validate_const
        validate_global
        validate_alias
      end

      def validate_type_application_constraints(type_name, type_params, type_args, location:)
        if type_params.size == type_args.size
          subst = Interface::Substitution.build(
            type_params.map(&:name),
            type_args.map {|type| factory.type(type) }
          )

          type_params.zip(type_args).each do |param, arg|
            arg or raise

            if param.upper_bound
              upper_bound_type = factory.type(param.upper_bound).subst(subst)
              arg_type = factory.type(arg)

              constraints = Subtyping::Constraints.empty

              checker.check(
                Subtyping::Relation.new(sub_type: arg_type, super_type: upper_bound_type),
                self_type: AST::Types::Self.instance,
                class_type: nil,
                instance_type: nil,
                constraints: constraints
              ).else do |result|
                @errors << Diagnostic::Signature::UnsatisfiableTypeApplication.new(
                  type_name: type_name,
                  type_arg: arg_type,
                  type_param: Interface::TypeParam.new(
                    name: param.name,
                    upper_bound: upper_bound_type,
                    variance: param.variance,
                    unchecked: param.unchecked?
                  ),
                  location: location
                )
              end
            end
          end
        end
      end

      def validate_type_application(type)
        name, type_params, type_args =
          case type
          when RBS::Types::ClassInstance
            [
              type.name,
              builder.build_instance(type.name).type_params_decl,
              type.args
            ]
          when RBS::Types::Interface
            [
              type.name,
              builder.build_interface(type.name).type_params_decl,
              type.args
            ]
          when RBS::Types::Alias
            type_name = env.normalize_type_name?(type.name) or return
            entry = env.type_alias_decls[type_name]

            [
              type_name,
              entry.decl.type_params,
              type.args
            ]
          end

        if name && type_params && type_args
          if !type_params.empty? && !type_args.empty?
            validate_type_application_constraints(name, type_params, type_args, location: type.location)
          end
        end

        type.each_type do |child|
          validate_type_application(child)
        end
      end

      def validate_type(type)
        Steep.logger.debug "#{Location.to_string type.location}: Validating #{type}..."

        validator.validate_type(type, context: nil)
        validate_type_application(type)
      end

      def ancestor_to_type(ancestor)
        case ancestor
        when RBS::Definition::Ancestor::Instance
          args = ancestor.args.map {|type| checker.factory.type(type) }

          case
          when ancestor.name.interface?
            AST::Types::Name::Interface.new(name: ancestor.name, args: args, location: nil)
          when ancestor.name.class?
            AST::Types::Name::Instance.new(name: ancestor.name, args: args, location: nil)
          else
            raise "#{ancestor.name}"
          end
        else
          raise "Unexpected ancestor: #{ancestor.inspect}"
        end
      end

      def mixin_constraints(definition, mixin_ancestors, immediate_self_types:)
        # @type var relations: Array[[Subtyping::Relation[AST::Types::t], RBS::Definition::Ancestor::Instance]]
        relations = []

        self_type = checker.factory.type(definition.self_type)
        if immediate_self_types && !immediate_self_types.empty?
          # @type var sts: Array[AST::Types::t]
          sts = immediate_self_types.map {|st| ancestor_to_type(st) }
          self_type = AST::Types::Intersection.build(types: sts.push(self_type), location: nil)
        end

        mixin_ancestors.each do |ancestor|
          args = ancestor.args.map {|type| checker.factory.type(type) }
          ancestor_ancestors = builder.ancestor_builder.one_instance_ancestors(ancestor.name)
          ancestor_ancestors.self_types or raise
          ancestor_ancestors.params or raise
          self_constraints = ancestor_ancestors.self_types.map do |self_ancestor|
            s = Interface::Substitution.build(ancestor_ancestors.params, args)
            ancestor_to_type(self_ancestor).subst(s)
          end

          self_constraints.each do |constraint|
            relations << [
              Subtyping::Relation.new(sub_type: self_type, super_type: constraint),
              ancestor
            ]
          end
        end

        relations
      end

      def each_method_type(definition)
        type_name = definition.type_name

        definition.methods.each_value do |method|
          if method.defined_in == type_name
            method.method_types.each do |method_type|
              yield method_type
            end
          end
        end
      end

      def each_variable_type(definition)
        type_name = definition.type_name

        definition.instance_variables.each_value do |var|
          if var.declared_in == type_name
            yield var.type
          end
        end

        definition.class_variables.each_value do |var|
          if var.declared_in == type_name
            yield var.type
          end
        end
      end

      def validate_definition_type(definition)
        each_method_type(definition) do |method_type|
          upper_bounds = method_type.type_params.each.with_object({}) do |param, hash|
            hash[param.name] = factory.type_opt(param.upper_bound)
          end

          checker.push_variable_bounds(upper_bounds) do
            method_type.each_type do |type|
              validate_type(type)
            end
          end
        end

        each_variable_type(definition) do |type|
          validate_type(type)
        end
      end

      def validate_one_class_decl(name)
        rescue_validation_errors(name) do
          Steep.logger.debug { "Validating class definition `#{name}`..." }

          Steep.logger.tagged "#{name}" do
            builder.build_instance(name).tap do |definition|
              upper_bounds = definition.type_params_decl.each.with_object({}) do |param, bounds|
                bounds[param.name] = factory.type_opt(param.upper_bound)
              end

              checker.push_variable_bounds(upper_bounds) do
                definition.instance_variables.each do |name, var|
                  if parent = var.parent_variable
                    var_type = checker.factory.type(var.type)
                    parent_type = checker.factory.type(parent.type)

                    relation = Subtyping::Relation.new(sub_type: var_type, super_type: parent_type)
                    result1 = checker.check(relation, self_type: nil, instance_type: nil, class_type: nil, constraints: Subtyping::Constraints.empty)
                    result2 = checker.check(relation.flip, self_type: nil, instance_type: nil, class_type: nil, constraints: Subtyping::Constraints.empty)

                    unless result1.success? and result2.success?
                      @errors << Diagnostic::Signature::InstanceVariableTypeError.new(
                        name: name,
                        location: var.type.location,
                        var_type: var_type,
                        parent_type: parent_type
                      )
                    end
                  end
                end

                ancestors = builder.ancestor_builder.one_instance_ancestors(name)
                mixin_constraints(definition, ancestors.included_modules || raise, immediate_self_types: ancestors.self_types).each do |relation, ancestor|
                  checker.check(
                    relation,
                    self_type: AST::Types::Self.instance,
                    instance_type: AST::Types::Instance.instance,
                    class_type: AST::Types::Class.instance,
                    constraints: Subtyping::Constraints.empty
                  ).else do
                    raise if ancestor.source.is_a?(Symbol)

                    @errors << Diagnostic::Signature::ModuleSelfTypeError.new(
                      name: name,
                      location: ancestor.source&.location || raise,
                      ancestor: ancestor,
                      relation: relation
                    )
                  end
                end

                ancestors.each_ancestor do |ancestor|
                  case ancestor
                  when RBS::Definition::Ancestor::Instance
                    validate_ancestor_application(name, ancestor)
                  end
                end

                validate_definition_type(definition)
              end
            end

            builder.build_singleton(name).tap do |definition|
              entry =
                case definition.entry
                when RBS::Environment::ClassEntry, RBS::Environment::ModuleEntry
                  definition.entry
                else
                  raise
                end

              definition.instance_variables.each do |name, var|
                if parent = var.parent_variable
                  var_type = checker.factory.type(var.type)
                  parent_type = checker.factory.type(parent.type)

                  relation = Subtyping::Relation.new(sub_type: var_type, super_type: parent_type)
                  result1 = checker.check(
                    relation,
                    self_type: AST::Types::Self.instance,
                    instance_type: AST::Types::Instance.instance,
                    class_type: AST::Types::Class.instance,
                    constraints: Subtyping::Constraints.empty
                  )
                  result2 = checker.check(
                    relation.flip,
                    self_type: AST::Types::Self.instance,
                    instance_type: AST::Types::Instance.instance,
                    class_type: AST::Types::Class.instance,
                    constraints: Subtyping::Constraints.empty
                  )

                  unless result1.success? and result2.success?
                    @errors << Diagnostic::Signature::InstanceVariableTypeError.new(
                      name: name,
                      location: var.type.location,
                      var_type: var_type,
                      parent_type: parent_type
                    )
                  end
                end
              end

              definition.class_variables.each do |name, var|
                if var.declared_in == definition.type_name
                  if (parent = var.parent_variable) && var.declared_in != parent.declared_in
                    class_var = entry.decls.flat_map {|decl| decl.decl.members }.find do |member|
                      member.is_a?(RBS::AST::Members::ClassVariable) && member.name == name
                    end

                    if class_var
                      loc = class_var.location #: RBS::Location[untyped, untyped]?
                      @errors << Diagnostic::Signature::ClassVariableDuplicationError.new(
                        class_name: definition.type_name,
                        other_class_name: parent.declared_in,
                        variable_name: name,
                        location: loc&.[](:name) || raise
                      )
                    end
                  end
                end
              end

              ancestors = builder.ancestor_builder.one_singleton_ancestors(name)
              ancestors.extended_modules or raise
              mixin_constraints(definition, ancestors.extended_modules, immediate_self_types: ancestors.self_types).each do |relation, ancestor|
                checker.check(
                  relation,
                  self_type: AST::Types::Self.instance ,
                  instance_type: AST::Types::Instance.instance,
                  class_type: AST::Types::Class.instance,
                  constraints: Subtyping::Constraints.empty
                ).else do
                  raise if ancestor.source.is_a?(Symbol)

                  @errors << Diagnostic::Signature::ModuleSelfTypeError.new(
                    name: name,
                    location: ancestor.source&.location || raise,
                    ancestor: ancestor,
                    relation: relation
                  )
                end
              end
              ancestors.each_ancestor do |ancestor|
                case ancestor
                when RBS::Definition::Ancestor::Instance
                  validate_ancestor_application(name, ancestor)
                end
              end

              validate_definition_type(definition)
            end
          end
        end
      end

      def validate_one_class(name)
        entry = env.constant_entry(name)

        case entry
        when RBS::Environment::ClassEntry, RBS::Environment::ModuleEntry
          validate_one_class_decl(name)
        when RBS::Environment::ClassAliasEntry, RBS::Environment::ModuleAliasEntry
          validate_one_class_alias(name, entry)
        end
      end

      def validate_ancestor_application(name, ancestor)
        unless ancestor.args.empty?
          definition =
            case
            when ancestor.name.class?
              builder.build_instance(ancestor.name)
            when ancestor.name.interface?
              builder.build_interface(ancestor.name)
            else
              raise
            end

          location =
            case ancestor.source
            when :super
              primary_decl = env.class_decls[name].primary.decl
              primary_decl.is_a?(RBS::AST::Declarations::Class) or raise
              if super_class = primary_decl.super_class
                super_class.location
              else
                # Implicit super class (Object): this can be skipped in fact...
                primary_decl.location&.aref(:name)
              end
            else
              ancestor.source&.location
            end

          validate_type_application_constraints(
            ancestor.name,
            definition.type_params_decl,
            ancestor.args,
            location: location
          )

          ancestor.args.each do |arg|
            validate_type(arg)
          end
        end
      end

      def validate_one_interface(name)
        rescue_validation_errors(name) do
          Steep.logger.debug "Validating interface `#{name}`..."
          Steep.logger.tagged "#{name}" do
            definition = builder.build_interface(name)

            upper_bounds = definition.type_params_decl.each.with_object({}) do |param, bounds|
              bounds[param.name] = factory.type_opt(param.upper_bound)
            end

            checker.push_variable_bounds(upper_bounds) do
              validate_definition_type(definition)

              ancestors = builder.ancestor_builder.one_interface_ancestors(name)
              ancestors.each_ancestor do |ancestor|
                case ancestor
                when RBS::Definition::Ancestor::Instance
                  # Interface ancestor cannot be other than Interface
                  ancestor.source.is_a?(Symbol) and raise

                  defn = builder.build_interface(ancestor.name)
                  validate_type_application_constraints(
                    ancestor.name,
                    defn.type_params_decl,
                    ancestor.args,
                    location: ancestor.source&.location || raise
                  )
                end
              end
            end
          end
        end
      end

      def validate_decl
        env.class_decls.each_key do |name|
          validate_one_class(name)
        end

        env.class_alias_decls.each do |name, entry|
          validate_one_class_alias(name, entry)
        end

        env.interface_decls.each_key do |name|
          validate_one_interface(name)
        end
      end

      def validate_const
        env.constant_decls.each do |name, entry|
          validate_one_constant(name, entry)
        end
      end

      def validate_one_constant(name, entry)
        rescue_validation_errors do
          Steep.logger.debug "Validating constant `#{name}`..."
          builder.ensure_namespace!(name.namespace, location: entry.decl.location)
          validate_type entry.decl.type
        end
      end

      def validate_global
        env.global_decls.each do |name, entry|
          validate_one_global(name, entry)
        end
      end

      def validate_one_global(name, entry)
        rescue_validation_errors do
          Steep.logger.debug "Validating global `#{name}`..."
          validate_type entry.decl.type
        end
      end

      def validate_one_alias(name, entry = env.type_alias_decls[name])
        rescue_validation_errors(name) do
          Steep.logger.debug "Validating alias `#{name}`..."

          unless name.namespace.empty?
            outer = name.namespace.to_type_name
            builder.validate_type_name(outer, entry.decl.location&.aref(:name))
          end

          upper_bounds = entry.decl.type_params.each.with_object({}) do |param, bounds|
            bounds[param.name] = factory.type_opt(param.upper_bound)
          end

          validator.validate_type_alias(entry: entry) do |type|
            checker.push_variable_bounds(upper_bounds) do
              validate_type(entry.decl.type)
            end
          end
        end
      end

      def validate_one_class_alias(name, entry)
        rescue_validation_errors(name) do
          Steep.logger.debug "Validating class/module alias `#{name}`..."
          validator.validate_class_alias(entry: entry)
        end
      end

      def validate_alias
        env.type_alias_decls.each do |name, entry|
          validate_one_alias(name, entry)
        end
      end

      def rescue_validation_errors(type_name = nil)
        yield
      rescue RBS::BaseError => exn
        @errors << Diagnostic::Signature.from_rbs_error(exn, factory: factory)
      end
    end
  end
end
