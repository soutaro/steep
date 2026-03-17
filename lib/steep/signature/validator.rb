module Steep
  module Signature
    class Validator
      Location = RBS::Location
      Declarations = RBS::AST::Declarations

      attr_reader :checker
      attr_reader :context

      def initialize(checker:)
        @checker = checker
        @errors = []
        @context = []
      end

      def push_context(self_type: latest_context[0], class_type: latest_context[1], instance_type: latest_context[2])
        @context.push([self_type, class_type, instance_type])
        yield
      ensure
        @context.pop
      end

      def latest_context
        context.last || [nil, nil, nil]
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
        @type_name_resolver ||= RBS::Resolver::TypeNameResolver.build(env)
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

            if param.upper_bound_type
              upper_bound_type = factory.type(param.upper_bound_type).subst(subst)
              arg_type = factory.type(arg)

              constraints = Subtyping::Constraints.empty

              self_type, class_type, instance_type = latest_context

              checker.check(
                Subtyping::Relation.new(sub_type: arg_type, super_type: upper_bound_type),
                self_type: self_type,
                class_type: class_type,
                instance_type: instance_type,
                constraints: constraints
              ).else do |result|
                @errors << Diagnostic::Signature::UnsatisfiableTypeApplication.new(
                  type_name: type_name,
                  type_arg: arg_type,
                  type_param: Interface::TypeParam.new(
                    name: param.name,
                    upper_bound: upper_bound_type,
                    variance: param.variance,
                    unchecked: param.unchecked?,
                    default_type: factory.type_opt(param.default_type)
                  ),
                  result: result,
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
            entry = env.type_alias_decls.fetch(type_name)

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
      end

      def validate_type(type)
        Steep.logger.debug { "#{Location.to_string type.location}: Validating #{type}..." }

        validator.validate_type(type, context: nil)
        validate_type_0(type)
      end

      def validate_type_0(type)
        validate_type_application(type)

        case type
        when RBS::Types::ClassInstance, RBS::Types::Interface, RBS::Types::ClassSingleton, RBS::Types::Alias
          type_name = type.name
          if type.location
            location = type.location[:name]
          end
        end

        if type_name && location
          validate_type_name_deprecation(type_name, location)
        end

        type.each_type do |child|
          validate_type_0(child)
        end
      end

      def validate_type_name_deprecation(type_name, location)
        if (_, message = AnnotationsHelper.deprecated_type_name?(type_name, env))
          @errors << Diagnostic::Signature::DeprecatedTypeName.new(type_name, message, location: location)
        end
      end

      def ancestor_to_type(ancestor)
        case ancestor
        when RBS::Definition::Ancestor::Instance
          args = ancestor.args.map {|type| checker.factory.type(type) }

          case
          when ancestor.name.interface?
            AST::Types::Name::Interface.new(name: ancestor.name, args: args)
          when ancestor.name.class?
            AST::Types::Name::Instance.new(name: ancestor.name, args: args)
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
          self_type = AST::Types::Intersection.build(types: sts.push(self_type))
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
          upper_bounds = method_type.type_params.each.with_object({}) do |param, hash| #$ Hash[Symbol, AST::Types::t?]
            hash[param.name] = factory.type_opt(param.upper_bound_type)
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

      def validate_type_params(type_name, type_params)
        if error_type_params = RBS::AST::TypeParam.validate(type_params)
          error_type_params.each do |type_param|
            default_type = type_param.default_type or raise
            @errors << Diagnostic::Signature::TypeParamDefaultReferenceError.new(type_param, location: default_type.location)
          end
        end

        upper_bounds = type_params.each.with_object({}) do |param, bounds| #$ Hash[Symbol, AST::Types::t?]
          bounds[param.name] = factory.type_opt(param.upper_bound_type)
        end

        checker.push_variable_bounds(upper_bounds) do
          type_params.each do |type_param|
            param = checker.factory.type_param(type_param)

            validate_type(type_param.upper_bound_type) if type_param.upper_bound_type
            validate_type(type_param.default_type) if type_param.default_type

            default_type = param.default_type or next
            upper_bound = param.upper_bound or next

            relation = Subtyping::Relation.new(sub_type: default_type, super_type: upper_bound)
            result = checker.check(relation, self_type: nil, instance_type: nil, class_type: nil, constraints: Subtyping::Constraints.empty)

            if result.failure?
              @errors << Diagnostic::Signature::UnsatisfiableGenericsDefaultType.new(
                type_param.name,
                result,
                location: (type_param.default_type || raise).location
              )
            end
          end
        end
      end

      def validate_one_class_decl(name, entry)
        rescue_validation_errors(name) do
          Steep.logger.debug { "Validating class definition `#{name}`..." }

          class_type = AST::Types::Name::Singleton.new(name: name)
          instance_type = AST::Types::Name::Instance.new(
            name: name,
            args: entry.type_params.map { AST::Types::Any.instance() }
          )

          entry.each_decl do |decl|
            if decl.is_a?(RBS::AST::Declarations::Base)
              unless AnnotationsHelper.deprecated_annotation?(decl.annotations)
                if location = decl.location
                  validate_type_name_deprecation(name, location[:name])
                end
              end
            end
          end

          Steep.logger.tagged "#{name}" do
            builder.build_instance(name).tap do |definition|
              upper_bounds = definition.type_params_decl.each.with_object({}) do |param, bounds| #$ Hash[Symbol, AST::Types::t?]
                bounds[param.name] = factory.type_opt(param.upper_bound_type)
              end

              self_type = AST::Types::Name::Instance.new(
                name: name,
                args: entry.type_params.map { AST::Types::Var.new(name: _1.name) }
              )

              push_context(self_type: self_type, class_type: class_type, instance_type: instance_type) do
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
                        result: _1
                      )
                    end
                  end

                  ancestors.each_ancestor do |ancestor|
                    case ancestor
                    when RBS::Definition::Ancestor::Instance
                      validate_ancestor_application(name, ancestor)
                      location =
                        case ancestor.source
                        when :super
                          if (primary_decl = entry.primary_decl).is_a?(RBS::AST::Declarations::Class)
                            primary_decl.super_class&.location
                          end
                        when nil
                          # skip
                        else
                          ancestor.source.location
                        end
                      if location
                        validate_type_name_deprecation(ancestor.name, location)
                      end
                    end
                  end

                  validate_definition_type(definition)
                end
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

              push_context(self_type: class_type, class_type: class_type, instance_type: instance_type) do
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
                      members = entry.each_decl.flat_map do |decl|
                        case decl
                        when RBS::AST::Declarations::Class, RBS::AST::Declarations::Module
                          decl.members
                        end
                      end
                      class_var = members.find do |member|
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
                      result: _1
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

            validate_type_params(name, entry.type_params)
          end
        end
      end

      def validate_one_class(name)
        entry = env.constant_entry(name)

        case entry
        when RBS::Environment::ClassEntry, RBS::Environment::ModuleEntry
          validate_one_class_decl(name, entry)
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
              primary_decl = env.class_decls.fetch(name).primary_decl
              unless primary_decl.is_a?(RBS::AST::Declarations::Class) || primary_decl.is_a?(RBS::AST::Ruby::Declarations::ClassDecl)
                raise
              end
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

            validate_type_params(name, definition.type_params_decl)

            upper_bounds = definition.type_params_decl.each.with_object({}) do |param, bounds| #$ Hash[Symbol, AST::Types::t?]
              bounds[param.name] = factory.type_opt(param.upper_bound_type)
            end

            self_type = AST::Types::Name::Interface.new(
              name: name,
              args: definition.type_params.map { AST::Types::Var.new(name: _1) }
            )

            push_context(self_type: self_type, class_type: nil, instance_type: nil) do
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

      def validate_one_alias(name, entry = env.type_alias_decls.fetch(name))
        inner_most_outer_module_name = entry.context&.last

        if inner_most_outer_module_name
          inner_most_outer_module = env.normalized_module_class_entry(inner_most_outer_module_name)
          if inner_most_outer_module
            class_type = AST::Types::Name::Singleton.new(name: inner_most_outer_module.name)
            instance_type = AST::Types::Name::Instance.new(
              name: inner_most_outer_module.name,
              args: inner_most_outer_module.type_params.map { AST::Types::Any.instance() },
            )
          end
        end

        push_context(class_type: class_type, instance_type: instance_type, self_type: nil) do
          rescue_validation_errors(name) do
            Steep.logger.debug "Validating alias `#{name}`..."

            unless name.namespace.empty?
              outer = name.namespace.to_type_name
              builder.validate_type_name(outer, entry.decl.location&.aref(:name))
            end

            validate_type_params(name, entry.decl.type_params)

            upper_bounds = entry.decl.type_params.each.with_object({}) do |param, bounds| #$ Hash[Symbol, AST::Types::t?]
              bounds[param.name] = factory.type_opt(param.upper_bound_type)
            end

            validator.validate_type_alias(entry: entry) do |type|
              checker.push_variable_bounds(upper_bounds) do
                validate_type(entry.decl.type)
              end
            end
          end
        end
      end

      def validate_one_class_alias(name, entry)
        rescue_validation_errors(name) do
          Steep.logger.debug "Validating class/module alias `#{name}`..."
          validator.validate_class_alias(entry: entry)
          if location = entry.decl.location
            validate_type_name_deprecation(entry.decl.old_name, location[:old_name])
          end
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
