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
        if block_given?
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
        @type_name_resolver ||= RBS::TypeNameResolver.from_env(env)
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

      def validate_type(type)
        Steep.logger.debug "#{Location.to_string type.location}: Validating #{type}..."
        validator.validate_type type, context: [RBS::Namespace.root]
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
        relations = []

        self_type = checker.factory.type(definition.self_type)
        if immediate_self_types && !immediate_self_types.empty?
          self_type = AST::Types::Intersection.build(
            types: immediate_self_types.map {|st| ancestor_to_type(st) }.push(self_type),
            location: nil
          )
        end

        mixin_ancestors.each do |ancestor|
          args = ancestor.args.map {|type| checker.factory.type(type) }
          ancestor_ancestors = builder.ancestor_builder.one_instance_ancestors(ancestor.name)
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

      def validate_one_class(name)
        rescue_validation_errors(name) do
          Steep.logger.debug { "Validating class definition `#{name}`..." }

          Steep.logger.tagged "#{name}" do
            builder.build_instance(name).tap do |definition|
              definition.instance_variables.each do |name, var|
                if parent = var.parent_variable
                  var_type = checker.factory.type(var.type)
                  parent_type = checker.factory.type(parent.type)

                  relation = Subtyping::Relation.new(sub_type: var_type, super_type: parent_type)
                  result1 = checker.check(
                    relation,
                    self_type: AST::Types::Self.new,
                    instance_type: AST::Types::Instance.new,
                    class_type: AST::Types::Class.new,
                    constraints: Subtyping::Constraints.empty
                  )
                  result2 = checker.check(
                    relation.flip,
                    self_type: AST::Types::Self.new,
                    instance_type: AST::Types::Instance.new,
                    class_type: AST::Types::Class.new,
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

              ancestors = builder.ancestor_builder.one_instance_ancestors(name)
              mixin_constraints(definition, ancestors.included_modules, immediate_self_types: ancestors.self_types).each do |relation, ancestor|
                checker.check(
                  relation,
                  self_type: AST::Types::Self.new,
                  instance_type: AST::Types::Instance.new,
                  class_type: AST::Types::Class.new,
                  constraints: Subtyping::Constraints.empty
                ).else do
                  @errors << Diagnostic::Signature::ModuleSelfTypeError.new(
                    name: name,
                    location: ancestor.source&.location || raise,
                    ancestor: ancestor,
                    relation: relation
                  )
                end
              end

              definition.each_type do |type|
                validate_type type
              end
            end

            builder.build_singleton(name).tap do |definition|
              definition.instance_variables.each do |name, var|
                if parent = var.parent_variable
                  var_type = checker.factory.type(var.type)
                  parent_type = checker.factory.type(parent.type)

                  relation = Subtyping::Relation.new(sub_type: var_type, super_type: parent_type)
                  result1 = checker.check(
                    relation,
                    self_type: AST::Types::Self.new,
                    instance_type: AST::Types::Instance.new,
                    class_type: AST::Types::Class.new,
                    constraints: Subtyping::Constraints.empty
                  )
                  result2 = checker.check(
                    relation.flip,
                    self_type: AST::Types::Self.new,
                    instance_type: AST::Types::Instance.new,
                    class_type: AST::Types::Class.new,
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

              ancestors = builder.ancestor_builder.one_singleton_ancestors(name)
              mixin_constraints(definition, ancestors.extended_modules, immediate_self_types: ancestors.self_types).each do |relation, ancestor|
                checker.check(
                  relation,
                  self_type: AST::Types::Self.new,
                  instance_type: AST::Types::Instance.new,
                  class_type: AST::Types::Class.new,
                  constraints: Subtyping::Constraints.empty
                ).else do
                  @errors << Diagnostic::Signature::ModuleSelfTypeError.new(
                    name: name,
                    location: ancestor.source&.location || raise,
                    ancestor: ancestor,
                    relation: relation
                  )
                end
              end

              definition.each_type do |type|
                validate_type type
              end
            end
          end
        end
      end

      def validate_one_interface(name)
        rescue_validation_errors(name) do
          Steep.logger.debug "Validating interface `#{name}`..."
          Steep.logger.tagged "#{name}" do
            builder.build_interface(name).each_type do |type|
              validate_type type
            end
          end
        end
      end

      def validate_decl
        env.class_decls.each_key do |name|
          validate_one_class(name)
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

      def validate_one_alias(name)
        rescue_validation_errors(name) do
          Steep.logger.debug "Validating alias `#{name}`..."
          builder.expand_alias1(name).tap do |type|
            validate_type(type)
          end
        end
      end

      def validate_alias
        env.alias_decls.each do |name, entry|
          validate_one_alias(name)
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
