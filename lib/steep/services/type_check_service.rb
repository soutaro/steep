module Steep
  module Services
    class TypeCheckService
      attr_reader :project
      attr_reader :signature_validation_diagnostics
      attr_reader :source_files
      attr_reader :signature_services

      class SourceFile
        attr_reader :path
        attr_reader :target
        attr_reader :content
        attr_reader :node
        attr_reader :typing
        attr_reader :errors
        attr_reader :ignores

        def initialize(path:, node:, content:, typing:, ignores:, errors:)
          @path = path
          @node = node
          @content = content
          @typing = typing
          @ignores = ignores
          @errors = errors
        end

        def self.with_syntax_error(path:, content:, error:)
          new(path: path, node: false, content: content, errors: [error], typing: nil, ignores: nil)
        end

        def self.with_typing(path:, content:, typing:, node:, ignores:)
          new(path: path, node: node, content: content, errors: nil, typing: typing, ignores: ignores)
        end

        def self.no_data(path:, content:)
          new(path: path, content: content, node: false, errors: nil, typing: nil, ignores: nil)
        end

        def update_content(content)
          self.class.new(
            path: path,
            content: content,
            node: node,
            errors: errors,
            typing: typing,
            ignores: ignores
          )
        end

        def diagnostics
          case
          when errors
            errors
          when typing && ignores
            errors = [] #: Array[Diagnostic::Ruby::Base]

            errors.concat(
              typing.errors.delete_if do |diagnostic|
                case diagnostic.location
                when ::Parser::Source::Range
                  ignores.ignore?(diagnostic.location.first_line, diagnostic.location.last_line, diagnostic.diagnostic_code)
                when RBS::Location
                  ignores.ignore?(diagnostic.location.start_line, diagnostic.location.end_line, diagnostic.diagnostic_code)
                end
              end
            )

            ignores.error_ignores.each do |ignore|
              errors << Diagnostic::Ruby::InvalidIgnoreComment.new(comment: ignore.comment)
            end

            errors
          else
            []
          end
        end
      end

      def initialize(project:)
        @project = project

        @source_files = {}
        @signature_services = project.targets.each.with_object({}) do |target, hash| #$ Hash[Symbol, SignatureService]
          loader = Project::Target.construct_env_loader(options: target.options, project: project)
          hash[target.name] = SignatureService.load_from(loader)
        end
        @signature_validation_diagnostics = project.targets.each.with_object({}) do |target, hash| #$ Hash[Symbol, Hash[Pathname, Array[Diagnostic::Signature::Base]]]
          hash[target.name] = {}
        end
      end

      def signature_diagnostics
        # @type var signature_diagnostics: Hash[Pathname, Array[Diagnostic::Signature::Base]]
        signature_diagnostics = {}

        project.targets.each do |target|
          service = signature_services[target.name]

          service.each_rbs_path do |path|
            signature_diagnostics[path] ||= []
          end

          case service.status
          when SignatureService::SyntaxErrorStatus, SignatureService::AncestorErrorStatus
            service.status.diagnostics.group_by {|diag| diag.location&.buffer&.name&.to_s }.each do |path_string, diagnostics|
              if path_string
                path = Pathname(path_string)
                signature_diagnostics[path].push(*diagnostics)
              end
            end
          when SignatureService::LoadedStatus
            validation_diagnostics = signature_validation_diagnostics[target.name] || {}
            validation_diagnostics.each do |path, diagnostics|
              signature_diagnostics[path].push(*diagnostics)
            end
          end
        end

        signature_diagnostics
      end

      def has_diagnostics?
        each_diagnostics.count > 0
      end

      def diagnostics
        each_diagnostics.to_h
      end

      def each_diagnostics(&block)
        if block
          signature_diagnostics.each do |path, diagnostics|
            yield [path, diagnostics]
          end

          source_files.each_value do |file|
            yield [file.path, file.diagnostics]
          end
        else
          enum_for :each_diagnostics
        end
      end

      def update(changes:)
        Steep.measure "#update_signature" do
          update_signature(changes: changes)
        end

        Steep.measure "#update_sources" do
          update_sources(changes: changes)
        end
      end

      def validate_signature(path:, target:)
        Steep.logger.tagged "#validate_signature(path=#{path})" do
          Steep.measure "validation" do
            service = signature_services[target.name]

            raise "#{path} is not library nor signature of #{target.name}" unless target.possible_signature_file?(path) || service.env_rbs_paths.include?(path)

            case service.status
            when SignatureService::SyntaxErrorStatus
              diagnostics = service.status.diagnostics.select do |diag|
                diag.location or raise
                Pathname(diag.location.buffer.name) == path &&
                  (diag.is_a?(Diagnostic::Signature::SyntaxError) || diag.is_a?(Diagnostic::Signature::UnexpectedError))
              end

            when SignatureService::AncestorErrorStatus
              diagnostics = service.status.diagnostics.select do |diag|
                diag.location or raise
                Pathname(diag.location.buffer.name) == path
              end

            when SignatureService::LoadedStatus
              validator = Signature::Validator.new(checker: service.current_subtyping || raise)
              type_names = service.type_names(paths: Set[path], env: service.latest_env).to_set

              unless type_names.empty?
                Steep.measure2 "Validating #{type_names.size} types" do |sampler|
                  type_names.each do |type_name|
                    sampler.sample(type_name.to_s) do
                      case
                      when type_name.class?
                        validator.validate_one_class(type_name)
                      when type_name.interface?
                        validator.validate_one_interface(type_name)
                      when type_name.alias?
                        validator.validate_one_alias(type_name)
                      end
                    end
                  end
                end
              end

              const_decls = service.const_decls(paths: Set[path], env: service.latest_env)
              unless const_decls.empty?
                Steep.measure2 "Validating #{const_decls.size} constants" do |sampler|
                  const_decls.each do |name, entry|
                    sampler.sample(name.to_s) do
                      validator.validate_one_constant(name, entry)
                    end
                  end
                end
              end

              global_decls = service.global_decls(paths: Set[path])
              unless global_decls.empty?
                Steep.measure2 "Validating #{global_decls.size} globals" do |sampler|
                  global_decls.each do |name, entry|
                    sampler.sample(name.to_s) do
                      validator.validate_one_global(name, entry)
                    end
                  end
                end
              end

              diagnostics = validator.each_error.select do |error|
                error.location or raise
                Pathname(error.location.buffer.name) == path
              end
            end

            signature_validation_diagnostics[target.name][path] = diagnostics
          end
        end
      end

      def typecheck_source(path:, target:)
        return unless target

        Steep.logger.tagged "#typecheck_source(path=#{path})" do
          Steep.measure "typecheck" do
            signature_service = signature_services[target.name]
            subtyping = signature_service.current_subtyping

            if subtyping
              text = source_files[path].content
              file = type_check_file(target: target, subtyping: subtyping, path: path, text: text) { signature_service.latest_constant_resolver }
              source_files[path] = file

              file.diagnostics
            end
          end
        end
      end

      def update_signature(changes:)
        Steep.logger.tagged "#update_signature" do
          signature_targets = {} #: Hash[Pathname, Project::Target]
          changes.each do |path, changes|
            target = project.targets.find { _1.possible_signature_file?(path) } or next
            signature_targets[path] = target
          end

          project.targets.each do |target|
            Steep.logger.tagged "#{target.name}" do
              # Load signatures from all project targets but `#unreferenced` ones
              target_changes = changes.select do |path, _|
                signature_target = signature_targets.fetch(path, nil) or next
                signature_target == target || !signature_target.unreferenced
              end

              unless target_changes.empty?
                signature_services.fetch(target.name).update(target_changes)
              end
            end
          end
        end
      end

      def update_sources(changes:)
        changes.each do |path, changes|
          if source_file?(path)
            file = source_files[path] || SourceFile.no_data(path: path, content: "")
            content = changes.inject(file.content) {|text, change| change.apply_to(text) }
            source_files[path] = file.update_content(content)
          end
        end
      end

      def type_check_file(target:, subtyping:, path:, text:)
        Steep.logger.tagged "#type_check_file(#{path}@#{target.name})" do
          source = Source.parse(text, path: path, factory: subtyping.factory)
          typing = TypeCheckService.type_check(source: source, subtyping: subtyping, constant_resolver: yield, cursor: nil)
          ignores = Source::IgnoreRanges.new(ignores: source.ignores)
          SourceFile.with_typing(path: path, content: text, node: source.node, typing: typing, ignores: ignores)
        end
      rescue AnnotationParser::SyntaxError => exn
        error = Diagnostic::Ruby::SyntaxError.new(message: exn.message, location: exn.location)
        SourceFile.with_syntax_error(path: path, content: text, error: error)
      rescue ::Parser::SyntaxError => exn
        error = Diagnostic::Ruby::SyntaxError.new(message: exn.message, location: (_ = exn).diagnostic.location)
        SourceFile.with_syntax_error(path: path, content: text, error: error)
      rescue EncodingError => exn
        SourceFile.no_data(path: path, content: "")
      rescue RuntimeError => exn
        Steep.log_error(exn)
        SourceFile.no_data(path: path, content: text)
      end

      def self.type_check(source:, subtyping:, constant_resolver:, cursor:)
        annotations = source.annotations(block: source.node, factory: subtyping.factory, context: nil)

        definition = subtyping.factory.definition_builder.build_instance(AST::Builtin::Object.module_name)

        const_env = TypeInference::ConstantEnv.new(
          factory: subtyping.factory,
          context: nil,
          resolver: constant_resolver
        )
        type_env = TypeInference::TypeEnv.new(const_env)
        type_env = TypeInference::TypeEnvBuilder.new(
          TypeInference::TypeEnvBuilder::Command::ImportConstantAnnotations.new(annotations),
          TypeInference::TypeEnvBuilder::Command::ImportGlobalDeclarations.new(subtyping.factory),
          TypeInference::TypeEnvBuilder::Command::ImportInstanceVariableDefinition.new(definition, subtyping.factory),
          TypeInference::TypeEnvBuilder::Command::ImportInstanceVariableAnnotations.new(annotations),
          TypeInference::TypeEnvBuilder::Command::ImportLocalVariableAnnotations.new(annotations)
        ).build(type_env)

        context = TypeInference::Context.new(
          block_context: nil,
          module_context: TypeInference::Context::ModuleContext.new(
            instance_type: AST::Builtin::Object.instance_type,
            module_type: AST::Builtin::Object.module_type,
            implement_name: nil,
            nesting: nil,
            class_name: AST::Builtin::Object.module_name,
            instance_definition: subtyping.factory.definition_builder.build_instance(AST::Builtin::Object.module_name),
            module_definition: subtyping.factory.definition_builder.build_singleton(AST::Builtin::Object.module_name)
          ),
          method_context: nil,
          break_context: nil,
          self_type: AST::Builtin::Object.instance_type,
          type_env: type_env,
          call_context: TypeInference::MethodCall::TopLevelContext.new,
          variable_context: TypeInference::Context::TypeVariableContext.empty
        )

        typing = Typing.new(source: source, root_context: context, cursor: cursor)

        construction = TypeConstruction.new(
          checker: subtyping,
          annotations: annotations,
          source: source,
          context: context,
          typing: typing
        )

        construction.synthesize(source.node) if source.node

        typing
      end

      def source_file?(path)
        source_files.key?(path) || (project.target_for_source_path(path) ? true : false)
      end

      def signature_file?(path)
        relative_path = project.relative_path(path)
        targets = signature_services.select {|_, sig| sig.files.key?(relative_path) || sig.env_rbs_paths.include?(path) }
        unless targets.empty?
          targets.keys
        end
      end

      def app_signature_file?(path)
        target_names = signature_services.select {|_, sig| sig.files.key?(path) }.keys
        unless target_names.empty?
          target_names
        end
      end

      def lib_signature_file?(path)
        signature_services.each_value.any? {|sig| sig.env_rbs_paths.include?(path) }
      end
    end
  end
end
