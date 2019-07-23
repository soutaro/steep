module Steep
  class Project
    class SignatureLoaded
      attr_reader :check
      attr_reader :loaded_at
      attr_reader :file_paths

      def initialize(check:, loaded_at:, file_paths:)
        @check = check
        @loaded_at = loaded_at
        @file_paths = file_paths
      end
    end

    class SignatureHasSyntaxError
      attr_reader :errors

      def initialize(errors:)
        @errors = errors
      end
    end

    class SignatureHasError
      attr_reader :errors

      def initialize(errors:)
        @errors = errors
      end
    end

    attr_reader :source_files
    attr_reader :signature_files
    attr_reader :listener
    attr_reader :original_environment

    attr_reader :signature

    def initialize(listener: nil, environment:)
      @listener = listener || NullListener.new
      @source_files = {}
      @signature_files = {}
      @original_environment = environment
    end

    def clear
      listener.clear_project project: self do
        @signature = nil
        source_files.each_value do |file|
          file.invalidate
        end
      end
    end

    def type_check(force_signatures: false, force_sources: false)
      listener.check(project: self) do
        should_reload_signature = force_signatures || signature_updated?
        reload_signature if should_reload_signature

        case sig = signature
        when SignatureLoaded
          each_updated_source(force: force_sources || should_reload_signature) do |file|
            file.invalidate

            listener.parse_source(project: self, file: file) do
              file.parse(factory: sig.check.factory)
            end

            listener.type_check_source(project: self, file: file) do
              file.type_check(sig.check)
            end
          end
        end
      end
    end

    def success?
      signature.is_a?(SignatureLoaded) &&
        source_files.all? {|_, file| file.source.is_a?(Source) && file.typing}
    end

    def has_type_error?
      source_files.any? do |_, file|
        file.errors&.any?
      end
    end

    def errors
      source_files.flat_map do |_, file|
        file.errors || []
      end
    end

    # @type method each_updated_source: (?force: bool) ?{ (SourceFile) -> any } -> any
    def each_updated_source(force: false)
      if block_given?
        source_files.each_value do |file|
          if force || file.requires_type_check?
            yield file
          end
        end
      else
        enum_for :each_updated_source, force: force
      end
    end

    def signature_updated?
      case sig = signature
      when SignatureLoaded
        signature_files.keys != sig.file_paths ||
          signature_files.any? {|_, file| file.content_updated_at >= sig.loaded_at}
      else
        true
      end
    end

    def reload_signature
      @signature = nil

      env = original_environment.dup

      # @type var syntax_errors: Hash<Pathname, any>
      syntax_errors = {}

      listener.load_signature(project: self) do
        signature_files.each_value do |file|
          sigs, buf = listener.parse_signature(project: self, file: file) do
            file.parse
          end

          env.buffers.push buf
          sigs.each do |sig|
            env << sig
          end
        rescue Ruby::Signature::SyntaxError, Ruby::Signature::SemanticsError => exn
          Steep.logger.warn {"Syntax error on #{file.path}: #{exn.inspect}"}
          syntax_errors[file.path] = exn
        end

        if syntax_errors.empty?
          listener.validate_signature(project: self) do
            definition_builder = Ruby::Signature::DefinitionBuilder.new(env: env)
            factory = AST::Types::Factory.new(builder: definition_builder)
            check = Subtyping::Check.new(factory: factory)

            errors = validate_signature(env: env, builder: definition_builder)

            @signature = if errors.empty?
                           SignatureLoaded.new(check: check, loaded_at: Time.now, file_paths: signature_files.keys)
                         else
                           SignatureHasError.new(errors: errors)
                         end
          end
        else
          @signature = SignatureHasSyntaxError.new(errors: syntax_errors)
        end
      end
    end

    def validate_signature(env:, builder:)
      errors = []

      begin
        env.each_decl do |name, decl|
          case decl
          when Ruby::Signature::AST::Declarations::Class, Ruby::Signature::AST::Declarations::Module
            Steep.logger.info { "#{Ruby::Signature::Location.to_string decl.location}:\tValidating class/module definition: `#{name}`..." }
            builder.build_instance(decl.name.absolute!).each_type do |type|
              env.validate type, namespace: Ruby::Signature::Namespace.root
            end
            builder.build_singleton(decl.name.absolute!).each_type do |type|
              env.validate type, namespace: Ruby::Signature::Namespace.root
            end
          when Ruby::Signature::AST::Declarations::Interface
            Steep.logger.info { "#{Ruby::Signature::Location.to_string decl.location}:\tValidating interface: `#{name}`..." }
            builder.build_interface(decl.name.absolute!, decl).each_type do |type|
              env.validate type, namespace: Ruby::Signature::Namespace.root
            end
          end
        end

        env.each_constant do |name, const|
          Steep.logger.info { "#{Ruby::Signature::Location.to_string const.location}:\tValidating constant: `#{name}`..." }
          env.validate const.type, namespace: name.namespace
        end

        env.each_global do |name, global|
          Steep.logger.info { "#{Ruby::Signature::Location.to_string global.location}:\tValidating global: `#{name}`..." }
          env.validate global.type, namespace: Namespace.root
        end

        env.each_alias do |name, decl|
          Steep.logger.info { "#{Ruby::Signature::Location.to_string decl.location}:\tValidating alias: `#{name}`..." }
          env.validate decl.type, namespace: name.namespace
        end

      rescue => exn
        errors << exn
      end

      errors
    end

    def type_of(path:, line:, column:)
      if source_file = source_files[path]
        case source = source_file.source
        when Source
          if typing = source_file.typing
            node = source.find_node(line: line, column: column)

            type = begin
              typing.type_of(node: node)
            rescue RuntimeError
              AST::Builtin.any_type
            end

            if block_given?
              yield type, node
            else
              type
            end
          end
        end
      end
    end
  end
end
