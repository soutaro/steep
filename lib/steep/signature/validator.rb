module Steep
  module Signature
    class Validator
      Location = Ruby::Signature::Location
      Declarations = Ruby::Signature::AST::Declarations

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
          @errors.each &block
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

      def factory
        checker.factory
      end

      def validate
        @errors = []

        validate_decl
        validate_const
        validate_global
      end

      def validate_decl
        env.each_decl do |name, decl|
          case decl
          when Declarations::Class
            rescue_validation_errors do
              Steep.logger.info "#{Location.to_string decl.location}:\tValidating class definition `#{name}`..."
              builder.build_instance(decl.name.absolute!).each_type do |type|
                env.validate type, namespace: Ruby::Signature::Namespace.root
              end
              builder.build_singleton(decl.name.absolute!).each_type do |type|
                env.validate type, namespace: Ruby::Signature::Namespace.root
              end
            end
          when Declarations::Interface
            rescue_validation_errors do
              Steep.logger.info "#{Location.to_string decl.location}:\tValidating interface `#{name}`..."
              builder.build_interface(decl.name.absolute!, decl).each_type do |type|
                env.validate type, namespace: Ruby::Signature::Namespace.root
              end
            end
          end
        end
      end

      def validate_const
        env.each_constant do |name, decl|
          rescue_validation_errors do
            Steep.logger.info "#{Location.to_string decl.location}:\tValidating constant `#{name}`..."
            env.validate(decl.type, namespace: name.namespace)
          end
        end
      end

      def validate_global
        env.each_global do |name, decl|
          rescue_validation_errors do
            Steep.logger.info "#{Location.to_string decl.location}:\tValidating global `#{name}`..."
            env.validate(decl.type, namespace: Ruby::Signature::Namespace.root)
          end
        end
      end

      def validate_alias
        env.each_alias do |name, decl|
          rescue_validation_errors do
            Steep.logger.info "#{Location.to_string decl.location}:\tValidating alias `#{name}`..."
            env.validate(decl.type, namespace: name.namespace)
          end
        end
      end

      def rescue_validation_errors
        yield
      rescue Ruby::Signature::InvalidTypeApplicationError => exn
        @errors << Errors::InvalidTypeApplicationError.new(
          name: factory.type_name(exn.type_name),
          args: exn.args.map {|ty| factory.type(ty) },
          params: exn.params,
          location: exn.location
        )
      rescue Ruby::Signature::NoTypeFoundError => exn
        @errors << Errors::UnknownTypeNameError.new(
          name: factory.type_name(exn.type_name),
          location: exn.location
        )
      end
    end
  end
end
