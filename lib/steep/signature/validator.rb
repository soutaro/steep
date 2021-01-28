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

      def validate_one_class(name)
        rescue_validation_errors(name) do
          Steep.logger.debug "Validating class definition `#{name}`..."
          Steep.logger.tagged "#{name}" do
            builder.build_instance(name).each_type do |type|
              validate_type type
            end
            builder.build_singleton(name).each_type do |type|
              validate_type type
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
          rescue_validation_errors do
            Steep.logger.debug "Validating constant `#{name}`..."
            builder.ensure_namespace!(name.namespace, location: entry.decl.location)
            validate_type entry.decl.type
          end
        end
      end

      def validate_global
        env.global_decls.each do |name, entry|
          rescue_validation_errors do
            Steep.logger.debug "Validating global `#{name}`..."
            validate_type entry.decl.type
          end
        end
      end

      def validate_alias
        env.alias_decls.each do |name, entry|
          rescue_validation_errors(name) do
            Steep.logger.debug "Validating alias `#{name}`..."
            builder.expand_alias(name).tap do |type|
              validate_type(type)
            end
          end
        end
      end

      def rescue_validation_errors(type_name = nil)
        yield
      rescue RBS::InvalidTypeApplicationError => exn
        @errors << Diagnostic::Signature::InvalidTypeApplicationError.new(
          name: exn.type_name,
          args: exn.args.map {|ty| factory.type(ty) },
          params: exn.params,
          location: exn.location
        )
      rescue RBS::NoTypeFoundError, RBS::NoSuperclassFoundError, RBS::NoMixinFoundError => exn
        @errors << Diagnostic::Signature::UnknownTypeNameError.new(
          name: exn.type_name,
          location: exn.location
        )
      rescue RBS::InvalidOverloadMethodError => exn
        @errors << Diagnostic::Signature::InvalidMethodOverloadError.new(
          class_name: exn.type_name,
          method_name: exn.method_name,
          location: exn.members[0].location
        )
      rescue RBS::DuplicatedMethodDefinitionError => exn
        @errors << Diagnostic::Signature::DuplicatedMethodDefinitionError.new(
          class_name: type_name,
          method_name: exn.method_name,
          location: exn.location
        )
      rescue RBS::DuplicatedInterfaceMethodDefinitionError => exn
        @errors << Diagnostic::Signature::DuplicatedMethodDefinitionError.new(
          class_name: type_name,
          method_name: exn.method_name,
          location: exn.member.location
        )
      rescue RBS::UnknownMethodAliasError => exn
        @errors << Diagnostic::Signature::UnknownMethodAliasError.new(
          class_name: type_name,
          method_name: exn.aliased_name,
          location: exn.location
        )
      rescue RBS::RecursiveAliasDefinitionError => exn
        @errors << Diagnostic::Signature::RecursiveAliasError.new(
          class_name: exn.type.name,
          names: exn.defs.map(&:name),
          location: exn.defs[0].original.location
        )
      rescue RBS::RecursiveAncestorError => exn
        @errors << Diagnostic::Signature::RecursiveAncestorError.new(
          ancestors: exn.ancestors,
          location: exn.location
        )
      end
    end
  end
end
