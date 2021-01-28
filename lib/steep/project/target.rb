module Steep
  class Project
    class Target
      attr_reader :name
      attr_reader :options

      attr_reader :source_patterns
      attr_reader :ignore_patterns
      attr_reader :signature_patterns

      attr_reader :source_files
      attr_reader :signature_files

      attr_reader :status

      SignatureErrorStatus = Struct.new(:timestamp, :errors, keyword_init: true)
      TypeCheckStatus = Struct.new(:environment, :subtyping, :type_check_sources, :timestamp, keyword_init: true)

      def initialize(name:, options:, source_patterns:, ignore_patterns:, signature_patterns:)
        @name = name
        @options = options
        @source_patterns = source_patterns
        @ignore_patterns = ignore_patterns
        @signature_patterns = signature_patterns

        @source_files = {}
        @signature_files = {}
      end

      def add_source(path, content = "")
        file = SourceFile.new(path: path)

        if block_given?
          file.content = yield
        else
          file.content = content
        end

        source_files[path] = file
      end

      def remove_source(path)
        source_files.delete(path)
      end

      def update_source(path, content = nil)
        file = source_files[path]
        if block_given?
          file.content = yield(file.content)
        else
          file.content = content || file.content
        end
      end

      def add_signature(path, content = "")
        file = SignatureFile.new(path: path)
        if block_given?
          file.content = yield
        else
          file.content = content
        end
        signature_files[path] = file
      end

      def remove_signature(path)
        signature_files.delete(path)
      end

      def update_signature(path, content = nil)
        file = signature_files[path]
        if block_given?
          file.content = yield(file.content)
        else
          file.content = content || file.content
        end
      end

      def source_file?(path)
        source_files.key?(path)
      end

      def signature_file?(path)
        signature_files.key?(path)
      end

      def possible_source_file?(path)
        self.class.test_pattern(source_patterns, path, ext: ".rb") &&
          !self.class.test_pattern(ignore_patterns, path, ext: ".rb")
      end

      def possible_signature_file?(path)
        self.class.test_pattern(signature_patterns, path, ext: ".rbs")
      end

      def self.test_pattern(patterns, path, ext:)
        patterns.any? do |pattern|
          p = pattern.end_with?(File::Separator) ? pattern : pattern + File::Separator
          p.delete_prefix!('./')
          (path.to_s.start_with?(p) && path.extname == ext) || File.fnmatch(pattern, path.to_s)
        end
      end

      def type_check(target_sources: source_files.values, validate_signatures: true)
        Steep.logger.tagged "target#type_check(target_sources: [#{target_sources.map(&:path).join(", ")}], validate_signatures: #{validate_signatures})" do
          Steep.measure "load signature and type check" do
            load_signatures(validate: validate_signatures) do |env, check, timestamp|
              Steep.measure "type checking #{target_sources.size} files" do
                run_type_check(env, check, timestamp, target_sources: target_sources)
              end
            end
          end
        end
      end

      def self.construct_env_loader(options:)
        repo = RBS::Repository.new(no_stdlib: options.vendor_path)
        options.repository_paths.each do |path|
          repo.add(path)
        end

        loader = RBS::EnvironmentLoader.new(
          core_root: options.vendor_path ? nil : RBS::EnvironmentLoader::DEFAULT_CORE_ROOT,
          repository: repo
        )
        loader.add(path: options.vendor_path) if options.vendor_path
        options.libraries.each do |lib|
          name, version = lib.split(/:/, 2)
          loader.add(library: name, version: version)
        end

        loader
      end

      def environment
        @environment ||= RBS::Environment.from_loader(Target.construct_env_loader(options: options))
      end

      def parse_signatures(timestamp:)
        updated_signature_files = []

        signature_files.each_value do |file|
          if !timestamp || file.content_updated_at >= timestamp
            Steep.logger.debug { "Loading #{file.path}..."}
            updated_signature_files << file
            file.load!()
          end
        end

        error_sigs = signature_files.each_value.reject {|file| file.status.is_a?(SignatureFile::DeclarationsStatus) }

        if error_sigs.empty?
          yield updated_signature_files
        else
          errors = error_sigs.map do |file|
            case error = file.status.error
            when RBS::Parser::SemanticsError
              Diagnostic::Signature::SyntaxError.new(error, location: error.location)
            when RBS::Parser::SyntaxError
              Diagnostic::Signature::SyntaxError.new(error, location: error.error_value.location)
            end
          end

          @status = SignatureErrorStatus.new(
            errors: errors,
            timestamp: Time.now
          )
        end
      end

      def load_decls(now:)
        errors = []
        env = environment.dup

        signature_files.each_value do |file|
          raise unless file.status.is_a?(SignatureFile::DeclarationsStatus)

          file.status.declarations.each do |decl|
            env << decl
          rescue RBS::DuplicatedDeclarationError => exn
            errors << Diagnostic::Signature::DuplicatedDeclarationError.new(
              type_name: exn.name,
              location: exn.decls[0].location
            )
          end
        end

        if errors.empty?
          yield env.resolve_type_names
        else
          @status = SignatureErrorStatus.new(
            errors: errors,
            timestamp: now
          )
        end
      end

      def load_signatures(validate:)
        timestamp = case status
                    when TypeCheckStatus
                      status.timestamp
                    end
        now = Time.now

        parse_signatures(timestamp: timestamp) do |updated_signature_files|
          if status.is_a?(TypeCheckStatus) && updated_signature_files.empty?
            yield status.environment, status.subtyping, status.timestamp
          else
            load_decls(now: now) do |env|
              definition_builder = RBS::DefinitionBuilder.new(env: env)
              factory = AST::Types::Factory.new(builder: definition_builder)
              check = Subtyping::Check.new(factory: factory)

              if validate
                validator = Signature::Validator.new(checker: check)
                validator.validate()

                if validator.no_error?
                  yield env, check, now
                else
                  @status = SignatureErrorStatus.new(
                    errors: validator.each_error.to_a,
                    timestamp: now
                  )
                end
              else
                yield env, check, Time.now
              end
            end
          end
        end
      end

      def run_type_check(env, check, timestamp, target_sources: source_files.values)
        type_check_sources = []

        target_sources.each do |file|
          Steep.logger.tagged("path=#{file.path}") do
            if file.type_check(check, timestamp)
              type_check_sources << file
            end
          end
        end

        @status = TypeCheckStatus.new(
          environment: env,
          subtyping: check,
          type_check_sources: type_check_sources,
          timestamp: timestamp
        )
      end

      def no_error?
        source_files.all? do |_, file|
          file.status.is_a?(Project::SourceFile::TypeCheckStatus)
        end
      end

      def errors
        case status
        when TypeCheckStatus
          source_files.each_value.flat_map(&:errors).select { |error | options.error_to_report?(error) }
        else
          []
        end
      end
    end
  end
end
