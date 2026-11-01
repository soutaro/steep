module Steep
  module Signature
    class Validator
      Location = RBS::Location
      Declarations = RBS::AST::Declarations
      Members = RBS::AST::Members
      RubyDeclarations = RBS::AST::Ruby::Declarations
      RubyMembers = RBS::AST::Ruby::Members

      attr_reader :checker
      attr_reader :context

      def initialize(checker:)
        @checker = checker
        @errors = []
        @error_keys = Set[]
        @context = []
        @validated_definitions = Set[]
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

      # Adds an error, unless the same kind of error is reported at the same location already
      #
      # The definition builder raises the error of a type name in a method type that the declaration reports too.
      #
      def push_error(error)
        if location = error.location
          key = [error.class, location.buffer.name, location.start_pos, location.end_pos] #: Array[untyped]
          return unless @error_keys.add?(key)
        end

        @errors << error
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
        @error_keys.clear
        @validated_definitions.clear

        env.sources.each do |source|
          validate_source(source)
        end
      end

      def validate_source(source)
        source.declarations.each do |decl|
          validate_declaration(decl, outer: nil)
        end
      end

      def validate_declaration(decl, outer:)
        case decl
        when Declarations::Class, Declarations::Module, RubyDeclarations::ClassDecl, RubyDeclarations::ModuleDecl
          name = class_decl_name(decl)
          validate_class_decl(decl)
          validate_class_definition(name)
          decl.each_decl do |nested|
            validate_declaration(nested, outer: name)
          end
        when Declarations::Interface
          validate_interface_decl(decl)
          validate_interface_definition(decl.name)
        when Declarations::TypeAlias
          validate_type_alias_decl(decl, outer: outer)
        when Declarations::Constant, RubyDeclarations::ConstantDecl
          validate_constant_decl(decl)
        when Declarations::Global
          validate_global_decl(decl)
        when Declarations::ClassAlias, Declarations::ModuleAlias, RubyDeclarations::ClassModuleAliasDecl
          validate_class_alias_decl(decl)
        end
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
                push_error Diagnostic::Signature::UnsatisfiableTypeApplication.new(
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
          push_error Diagnostic::Signature::DeprecatedTypeName.new(type_name, message, location: location)
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

      def validate_type_params(type_name, type_params)
        if error_type_params = RBS::AST::TypeParam.validate(type_params)
          error_type_params.each do |type_param|
            default_type = type_param.default_type or raise
            push_error Diagnostic::Signature::TypeParamDefaultReferenceError.new(type_param, location: default_type.location)
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
              push_error Diagnostic::Signature::UnsatisfiableGenericsDefaultType.new(
                type_param.name,
                result,
                location: (type_param.default_type || raise).location
              )
            end
          end
        end
      end

      def validate_method_type(method_type)
        upper_bounds = method_type.type_params.each.with_object({}) do |param, hash| #$ Hash[Symbol, AST::Types::t?]
          hash[param.name] = factory.type_opt(param.upper_bound_type)
        end

        checker.push_variable_bounds(upper_bounds) do
          method_type.each_type do |type|
            validate_type(type)
          end
        end
      end

      def validate_ancestor(type_name, args, location)
        if location
          validate_type_name_deprecation(type_name, location)
        end

        return if args.empty?

        type_params =
          case
          when type_name.class?
            # The definition reports the unknown module
            name = env.normalize_module_name?(type_name) or return
            builder.build_instance(name).type_params_decl
          when type_name.interface?
            return unless env.interface_decls.key?(type_name)
            builder.build_interface(type_name).type_params_decl
          else
            return
          end

        validate_type_application_constraints(type_name, type_params, args, location: location)

        args.each do |arg|
          validate_type(arg)
        end
      end

      def class_decl_name(decl)
        case decl
        when Declarations::Class, Declarations::Module
          decl.name
        when RubyDeclarations::ClassDecl
          decl.class_name
        when RubyDeclarations::ModuleDecl
          decl.module_name
        end
      end

      def validate_class_decl(decl)
        name = class_decl_name(decl)
        type_params = decl.type_params

        Steep.logger.debug { "Validating class declaration `#{name}`..." }

        class_type = AST::Types::Name::Singleton.new(name: name)
        instance_type = AST::Types::Name::Instance.new(
          name: name,
          args: type_params.map { AST::Types::Any.instance() }
        )
        self_type = AST::Types::Name::Instance.new(
          name: name,
          args: type_params.map { AST::Types::Var.new(name: _1.name) }
        )
        upper_bounds = type_params.each.with_object({}) do |param, bounds| #$ Hash[Symbol, AST::Types::t?]
          bounds[param.name] = factory.type_opt(param.upper_bound_type)
        end

        rescue_validation_errors(name) do
          if decl.is_a?(Declarations::Base)
            unless AnnotationsHelper.deprecated_annotation?(decl.annotations)
              if location = decl.location
                validate_type_name_deprecation(name, location[:name])
              end
            end
          end

          validate_type_params(name, type_params)
        end

        push_context(self_type: self_type, class_type: class_type, instance_type: instance_type) do
          checker.push_variable_bounds(upper_bounds) do
            case decl
            when Declarations::Class
              if super_class = decl.super_class
                rescue_validation_errors(name) do
                  validate_ancestor(super_class.name, super_class.args, super_class.location)
                end
              end
            when RubyDeclarations::ClassDecl
              if super_class = decl.super_class
                rescue_validation_errors(name) do
                  validate_ancestor(super_class.type_name, super_class.type_args, super_class.location)
                end
              end
            when Declarations::Module, RubyDeclarations::ModuleDecl
              decl.self_types.each do |self_type|
                rescue_validation_errors(name) do
                  validate_ancestor(self_type.name, self_type.args, self_type.location)
                end
              end
            end

            decl.members.each do |member|
              validate_member(name, member, class_type: class_type, instance_type: instance_type)
            end
          end
        end
      end

      def validate_member(type_name, member, class_type:, instance_type:)
        rescue_validation_errors(type_name) do
          case member
          when Members::MethodDefinition, RubyMembers::DefMember
            member.overloads.each do |overload|
              validate_method_type(overload.method_type) if member.instance?
              if member.singleton?
                push_context(self_type: class_type, class_type: class_type, instance_type: instance_type) do
                  validate_method_type(overload.method_type)
                end
              end
            end
          when Members::AttrReader, Members::AttrWriter, Members::AttrAccessor
            if member.kind == :singleton
              push_context(self_type: class_type, class_type: class_type, instance_type: instance_type) do
                validate_type(member.type)
              end
            else
              validate_type(member.type)
            end
          when RubyMembers::AttributeMember
            if type = member.type
              validate_type(type)
            end
          when Members::InstanceVariable, Members::ClassVariable, RubyMembers::InstanceVariableMember
            validate_type(member.type)
          when Members::ClassInstanceVariable
            push_context(self_type: class_type, class_type: class_type, instance_type: instance_type) do
              validate_type(member.type)
            end
          when Members::Include, Members::Prepend
            validate_ancestor(member.name, member.args, member.location)
          when RubyMembers::IncludeMember, RubyMembers::PrependMember
            validate_ancestor(member.module_name, member.type_args, member.location)
          when Members::Extend
            push_context(self_type: class_type, class_type: class_type, instance_type: instance_type) do
              validate_ancestor(member.name, member.args, member.location)
            end
          when RubyMembers::ExtendMember
            push_context(self_type: class_type, class_type: class_type, instance_type: instance_type) do
              validate_ancestor(member.module_name, member.type_args, member.location)
            end
          end
        end
      end

      def validate_class_definition(name)
        return unless @validated_definitions.add?(name)

        rescue_validation_errors(name) do
          Steep.logger.debug { "Validating class definition `#{name}`..." }

          class_type = AST::Types::Name::Singleton.new(name: name)

          Steep.logger.tagged "#{name}" do
            builder.build_instance(name).tap do |definition|
              instance_type = AST::Types::Name::Instance.new(
                name: name,
                args: definition.type_params_decl.map { AST::Types::Any.instance() }
              )

              upper_bounds = definition.type_params_decl.each.with_object({}) do |param, bounds| #$ Hash[Symbol, AST::Types::t?]
                bounds[param.name] = factory.type_opt(param.upper_bound_type)
              end

              self_type = AST::Types::Name::Instance.new(
                name: name,
                args: definition.type_params_decl.map { AST::Types::Var.new(name: _1.name) }
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
                        push_error Diagnostic::Signature::InstanceVariableTypeError.new(
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

                      push_error Diagnostic::Signature::ModuleSelfTypeError.new(
                        name: name,
                        location: ancestor.source&.location || raise,
                        ancestor: ancestor,
                        result: _1
                      )
                    end
                  end
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

              instance_type = AST::Types::Name::Instance.new(
                name: name,
                args: entry.type_params.map { AST::Types::Any.instance() }
              )

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
                      push_error Diagnostic::Signature::InstanceVariableTypeError.new(
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
                        push_error Diagnostic::Signature::ClassVariableDuplicationError.new(
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

                    push_error Diagnostic::Signature::ModuleSelfTypeError.new(
                      name: name,
                      location: ancestor.source&.location || raise,
                      ancestor: ancestor,
                      result: _1
                    )
                  end
                end
              end
            end
          end
        end
      end

      def validate_interface_decl(decl)
        name = decl.name

        Steep.logger.debug { "Validating interface declaration `#{name}`..." }

        rescue_validation_errors(name) do
          validate_type_params(name, decl.type_params)
        end

        upper_bounds = decl.type_params.each.with_object({}) do |param, bounds| #$ Hash[Symbol, AST::Types::t?]
          bounds[param.name] = factory.type_opt(param.upper_bound_type)
        end

        self_type = AST::Types::Name::Interface.new(
          name: name,
          args: decl.type_params.map { AST::Types::Var.new(name: _1.name) }
        )

        push_context(self_type: self_type, class_type: nil, instance_type: nil) do
          checker.push_variable_bounds(upper_bounds) do
            decl.members.each do |member|
              rescue_validation_errors(name) do
                case member
                when Members::MethodDefinition
                  member.overloads.each do |overload|
                    validate_method_type(overload.method_type)
                  end
                when Members::Include
                  validate_ancestor(member.name, member.args, member.location)
                end
              end
            end
          end
        end
      end

      def validate_interface_definition(name)
        return unless @validated_definitions.add?(name)

        rescue_validation_errors(name) do
          Steep.logger.debug { "Validating interface definition `#{name}`..." }
          builder.build_interface(name)
        end
      end

      def validate_type_alias_decl(decl, outer:)
        name = decl.name

        if outer
          outer_entry = env.module_class_entry(outer, normalized: true)
          if outer_entry
            class_type = AST::Types::Name::Singleton.new(name: outer_entry.name)
            instance_type = AST::Types::Name::Instance.new(
              name: outer_entry.name,
              args: outer_entry.type_params.map { AST::Types::Any.instance() },
            )
          end
        end

        push_context(class_type: class_type, instance_type: instance_type, self_type: nil) do
          rescue_validation_errors(name) do
            Steep.logger.debug "Validating alias `#{name}`..."

            unless name.namespace.empty?
              outer_name = name.namespace.to_type_name
              builder.validate_type_name(outer_name, decl.location&.aref(:name))
            end

            validate_type_params(name, decl.type_params)

            upper_bounds = decl.type_params.each.with_object({}) do |param, bounds| #$ Hash[Symbol, AST::Types::t?]
              bounds[param.name] = factory.type_opt(param.upper_bound_type)
            end

            entry = env.type_alias_decls.fetch(name)
            validator.validate_type_alias(entry: entry) do |type|
              checker.push_variable_bounds(upper_bounds) do
                validate_type(decl.type)
              end
            end
          end
        end
      end

      def validate_constant_decl(decl)
        name =
          case decl
          when Declarations::Constant
            decl.name
          when RubyDeclarations::ConstantDecl
            decl.constant_name
          end

        rescue_validation_errors do
          Steep.logger.debug "Validating constant `#{name}`..."
          builder.ensure_namespace!(name.namespace, location: decl.location)
          if type = decl.type
            validate_type(type)
          end
        end
      end

      def validate_global_decl(decl)
        rescue_validation_errors do
          Steep.logger.debug "Validating global `#{decl.name}`..."
          validate_type(decl.type)
        end
      end

      def validate_class_alias_decl(decl)
        name = decl.new_name

        rescue_validation_errors(name) do
          Steep.logger.debug "Validating class/module alias `#{name}`..."

          entry = env.class_alias_decls.fetch(name)
          validator.validate_class_alias(entry: entry)

          case decl
          when Declarations::ClassAlias, Declarations::ModuleAlias
            if location = decl.location
              validate_type_name_deprecation(decl.old_name, location[:old_name])
            end
          when RubyDeclarations::ClassModuleAliasDecl
            if (annotation = decl.annotation) && (old_name = annotation.type_name) && (location = annotation.type_name_location)
              validate_type_name_deprecation(old_name, location)
            end
          end
        end
      end

      def validate_one_class(name)
        entry = env.constant_entry(name)

        case entry
        when RBS::Environment::ClassEntry, RBS::Environment::ModuleEntry
          entry.each_decl do |decl|
            validate_class_decl(decl)
          end
          validate_class_definition(name)
        when RBS::Environment::ClassAliasEntry, RBS::Environment::ModuleAliasEntry
          validate_class_alias_decl(entry.decl)
        end
      end

      def validate_one_interface(name)
        entry = env.interface_decls.fetch(name)
        validate_interface_decl(entry.decl)
        validate_interface_definition(name)
      end

      def validate_one_alias(name, entry = env.type_alias_decls.fetch(name))
        validate_type_alias_decl(entry.decl, outer: entry.context&.last || nil)
      end

      def validate_one_constant(name, entry)
        validate_constant_decl(entry.decl)
      end

      def validate_one_global(name, entry)
        validate_global_decl(entry.decl)
      end

      def validate_one_class_alias(name, entry)
        validate_class_alias_decl(entry.decl)
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

      def validate_global
        env.global_decls.each do |name, entry|
          validate_one_global(name, entry)
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
        push_error Diagnostic::Signature.from_rbs_error(exn, factory: factory)
      end
    end
  end
end
