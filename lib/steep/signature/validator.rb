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
      end

      def validate_type(type)
        Steep.logger.debug "#{Location.to_string type.location}: Validating #{type}..."
        validator.validate_type type, context: [RBS::Namespace.root]
      end

      def validate_one_class(name)
        rescue_validation_errors do
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
        rescue_validation_errors do
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
          rescue_validation_errors do
            Steep.logger.debug "Validating alias `#{name}`..."
            validate_type(entry.decl.type)
          end
        end
      end

      def rescue_validation_errors
        yield
      rescue RBS::InvalidTypeApplicationError => exn
        @errors << Errors::InvalidTypeApplicationError.new(
          name: factory.type_name(exn.type_name),
          args: exn.args.map {|ty| factory.type(ty) },
          params: exn.params,
          location: exn.location
        )
      rescue RBS::NoTypeFoundError => exn
        @errors << Errors::UnknownTypeNameError.new(
          name: factory.type_name(exn.type_name),
          location: exn.location
        )
      end
    end
  end
end
