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

      SignatureSyntaxErrorStatus = Struct.new(:timestamp, :errors, keyword_init: true)
      SignatureValidationErrorStatus = Struct.new(:timestamp, :errors, keyword_init: true)
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

      def add_source(path, content)
        file = SourceFile.new(path: path)
        file.content = content
        source_files[path] = file
      end

      def remove_source(path)
        source_files.delete(path)
      end

      def update_source(path, content)
        file = source_files[path]
        file.content = content
      end

      def add_signature(path, content)
        file = SignatureFile.new(path: path)
        file.content = content
        signature_files[path] = file
      end

      def remove_signature(path)
        signature_files.delete(path)
      end

      def update_signature(path, content)
        file = signature_files[path]
        file.content = content
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

      def environment
        @environment ||= RBS::Environment.new().yield_self do |env|
          stdlib_root = options.vendored_stdlib_path || RBS::EnvironmentLoader::STDLIB_ROOT
          gem_vendor_path = options.vendored_gems_path
          loader = RBS::EnvironmentLoader.new(stdlib_root: stdlib_root, gem_vendor_path: gem_vendor_path)
          options.libraries.each do |lib|
            loader.add(library: lib)
          end
          loader.load(env: env)

          env.resolve_type_names
        end
      end

      def load_signatures(validate:)
        timestamp = case status
                    when TypeCheckStatus
                      status.timestamp
                    end

        updated_files = []

        signature_files.each_value do |file|
          if !timestamp || file.content_updated_at >= timestamp
            updated_files << file
            file.load!()
          end
        end

        if signature_files.each_value.all? {|file| file.status.is_a?(SignatureFile::DeclarationsStatus) }
          if status.is_a?(TypeCheckStatus) && updated_files.empty?
            yield status.environment, status.subtyping, status.timestamp
          else
            env = environment.dup

            signature_files.each_value do |file|
              if file.status.is_a?(SignatureFile::DeclarationsStatus)
                file.status.declarations.each do |decl|
                  env << decl
                end
              end
            end

            env = env.resolve_type_names

            definition_builder = RBS::DefinitionBuilder.new(env: env)
            factory = AST::Types::Factory.new(builder: definition_builder)
            check = Subtyping::Check.new(factory: factory)

            if validate
              validator = Signature::Validator.new(checker: check)
              validator.validate()

              if validator.no_error?
                yield env, check, Time.now
              else
                @status = SignatureValidationErrorStatus.new(
                  errors: validator.each_error.to_a,
                  timestamp: Time.now
                )
              end
            else
              yield env, check, Time.now
            end
          end

        else
          errors = signature_files.each_value.with_object([]) do |file, errors|
            if file.status.is_a?(SignatureFile::ParseErrorStatus)
              errors << file.status.error
            end
          end

          @status = SignatureSyntaxErrorStatus.new(
            errors: errors,
            timestamp: Time.now
          )
        end
      end

      def run_type_check(env, check, timestamp, target_sources: source_files.values)
        type_check_sources = []

        target_sources.each do |file|
          if file.type_check(check, timestamp)
            type_check_sources << file
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
          source_files.each_value.flat_map(&:errors)
        else
          []
        end
      end
    end
  end
end
