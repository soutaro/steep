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

    attr_reader :signature

    def initialize(listener = nil)
      @listener = listener || NullListener.new
      @source_files = {}
      @signature_files = {}
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
              file.parse()
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
        source_files.all? {|_, file| file.source.is_a?(Source) && file.typing }
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
          signature_files.any? {|_, file| file.content_updated_at >= sig.loaded_at }
      else
        true
      end
    end

    def reload_signature
      @signature = nil

      env = AST::Signature::Env.new
      builder = Interface::Builder.new(signatures: env)
      check = Subtyping::Check.new(builder: builder)

      # @type var syntax_errors: Hash<Pathname, any>
      syntax_errors = {}

      listener.load_signature(project: self) do
        signature_files.each_value do |file|
          sigs = listener.parse_signature(project: self, file: file) do
            file.parse
          end

          sigs.each do |sig|
            env.add sig
          end
        rescue Racc::ParseError => exn
          Steep.logger.warn { "Syntax error on #{file.path}: #{exn.inspect}" }
          syntax_errors[file.path] = exn
        end

        if syntax_errors.empty?
          listener.validate_signature(project: self) do
            errors = validate_signature(check)
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

    def validate_signature(check)
      errors = []

      builder = check.builder

      check.builder.signatures.each do |sig|
        Steep.logger.debug { "Validating signature: #{sig.inspect}" }

        case sig
        when AST::Signature::Interface
          yield_self do
            instance_interface = builder.build_interface(sig.name)

            args = instance_interface.params.map {|var| AST::Types::Var.fresh(var) }
            instance_type = AST::Types::Name::Interface.new(name: sig.name, args: args)

            instance_interface.instantiate(type: instance_type,
                                           args: args,
                                           instance_type: instance_type,
                                           module_type: nil).validate(check)
          end

        when AST::Signature::Module
          yield_self do
            instance_interface = builder.build_instance(sig.name)
            instance_args = instance_interface.params.map {|var| AST::Types::Var.fresh(var) }

            module_interface = builder.build_module(sig.name)
            module_args = module_interface.params.map {|var| AST::Types::Var.fresh(var) }

            instance_type = AST::Types::Name::Instance.new(name: sig.name, args: instance_args)
            module_type = AST::Types::Name::Module.new(name: sig.name)

            Steep.logger.debug { "Validating instance methods..." }
            instance_interface.instantiate(type: instance_type,
                                           args: instance_args,
                                           instance_type: instance_type,
                                           module_type: module_type).validate(check)

            Steep.logger.debug { "Validating class methods..." }
            module_interface.instantiate(type: module_type,
                                         args: module_args,
                                         instance_type: instance_type,
                                         module_type: module_type).validate(check)
          end

        when AST::Signature::Class
          yield_self do
            instance_interface = builder.build_instance(sig.name)
            instance_args = instance_interface.params.map {|var| AST::Types::Var.fresh(var) }

            module_interface = builder.build_class(sig.name, constructor: true)
            module_args = module_interface.params.map {|var| AST::Types::Var.fresh(var) }

            instance_type = AST::Types::Name::Instance.new(name: sig.name, args: instance_args)
            module_type = AST::Types::Name::Class.new(name: sig.name, constructor: true)

            Steep.logger.debug { "Validating instance methods..." }
            instance_interface.instantiate(type: instance_type,
                                           args: instance_args,
                                           instance_type: instance_type,
                                           module_type: module_type).validate(check)

            Steep.logger.debug { "Validating class methods..." }
            module_interface.instantiate(type: module_type,
                                         args: module_args,
                                         instance_type: instance_type,
                                         module_type: module_type).validate(check)
          end
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
