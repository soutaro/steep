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

        def initialize(path:, node:, content:, typing:, errors:)
          @path = path
          @node = node
          @content = content
          @typing = typing
          @errors = errors
        end

        def self.with_syntax_error(path:, content:, error:)
          new(path: path, node: false, content: content, errors: [error], typing: nil)
        end

        def self.with_typing(path:, content:, typing:, node:)
          new(path: path, node: node, content: content, errors: nil, typing: typing)
        end

        def self.no_data(path:, content:)
          new(path: path, content: content, node: false, errors: nil, typing: nil)
        end

        def update_content(content)
          self.class.new(
            path: path,
            content: content,
            node: node,
            errors: errors,
            typing: typing
          )
        end

        def diagnostics
          errors || typing&.errors || []
        end
      end

      class TargetRequest
        attr_reader :target
        attr_reader :source_paths

        def initialize(target:)
          @target = target
          @source_paths = Set[]
          @signature_updated = false
        end

        def signature_updated!(value = true)
          @signature_updated = value
          self
        end

        def signature_updated?
          @signature_updated
        end

        def empty?
          !signature_updated? && source_paths.empty?
        end

        def ==(other)
          other.is_a?(TargetRequest) &&
            other.target == target &&
            other.source_paths == source_paths &&
            other.signature_updated? == signature_updated?
        end

        alias eql? ==

        def hash
          self.class.hash ^ target.hash ^ source_paths.hash ^ @signature_updated.hash
        end
      end

      def initialize(project:)
        @project = project

        @source_files = {}
        @signature_services = project.targets.each.with_object({}) do |target, hash|
          loader = Project::Target.construct_env_loader(options: target.options, project: project)
          hash[target.name] = SignatureService.load_from(loader)
        end
        @signature_validation_diagnostics = project.targets.each.with_object({}) do |target, hash|
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
            service.status.diagnostics.group_by {|diag| Pathname(diag.location.buffer.name) }.each do |path, diagnostics|
              signature_diagnostics[path].push(*diagnostics)
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
        requests = project.targets.each_with_object({}.compare_by_identity) do |target, hash|
          hash[target] = TargetRequest.new(target: target)
        end

        Steep.measure "#update_signature" do
          update_signature(changes: changes, requests: requests)
        end

        Steep.measure "#update_sources" do
          update_sources(changes: changes, requests: requests)
        end

        requests.transform_keys(&:name).reject {|_, request| request.empty? }
      end

      def update_and_check(changes:, assignment:, &block)
        requests = update(changes: changes)

        signatures = requests.each_value.with_object(Set[]) do |request, sigs|
          if request.signature_updated?
            service = signature_services[request.target.name]
            sigs.merge(service.each_rbs_path)
          end
        end

        signatures.each do |path|
          if assignment =~ path
            validate_signature(path: path, &block)
          end
        end

        requests.each_value do |request|
          request.source_paths.each do |path|
            if assignment =~ path
              typecheck_source(path: path, target: request.target, &block)
            end
          end
        end
      end

      def validate_signature(path:, &block)
        Steep.logger.tagged "#validate_signature(path=#{path})" do
          Steep.measure "validation" do
            # @type var accumulated_diagnostics: Array[Diagnostic::Signature::Base]
            accumulated_diagnostics = []

            project.targets.each do |target|
              service = signature_services[target.name]

              next unless target.possible_signature_file?(path) || service.env_rbs_paths.include?(path)

              case service.status
              when SignatureService::SyntaxErrorStatus
                diagnostics = service.status.diagnostics.select do |diag|
                  Pathname(diag.location.buffer.name) == path &&
                    (diag.is_a?(Diagnostic::Signature::SyntaxError) || diag.is_a?(Diagnostic::Signature::UnexpectedError))
                end
                accumulated_diagnostics.push(*diagnostics)
                unless diagnostics.empty?
                  yield [path, accumulated_diagnostics]
                end

              when SignatureService::AncestorErrorStatus
                diagnostics = service.status.diagnostics.select {|diag| Pathname(diag.location.buffer.name) == path }
                accumulated_diagnostics.push(*diagnostics)
                yield [path, accumulated_diagnostics]

              when SignatureService::LoadedStatus
                validator = Signature::Validator.new(checker: service.current_subtyping)
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

                diagnostics = validator.each_error.select {|error| Pathname(error.location.buffer.name) == path }
                accumulated_diagnostics.push(*diagnostics)
                yield [path, accumulated_diagnostics]
              end

              signature_validation_diagnostics[target.name][path] = diagnostics
            end
          end
        end
      end

      def typecheck_source(path:, target: project.target_for_source_path(path), &block)
        return unless target

        Steep.logger.tagged "#typecheck_source(path=#{path})" do
          Steep.measure "typecheck" do
            signature_service = signature_services[target.name]
            subtyping = signature_service.current_subtyping

            if subtyping
              text = source_files[path].content
              file = type_check_file(target: target, subtyping: subtyping, path: path, text: text) { signature_service.latest_constant_resolver }
              yield [file.path, file.diagnostics]
              source_files[path] = file
            end
          end
        end
      end

      def update_signature(changes:, requests:)
        Steep.logger.tagged "#update_signature" do
          project.targets.each do |target|
            signature_service = signature_services[target.name]
            signature_changes = changes.filter {|path, _| target.possible_signature_file?(path) }

            unless signature_changes.empty?
              requests[target].signature_updated!
              signature_service.update(signature_changes)
            end
          end
        end
      end

      def update_sources(changes:, requests:)
        requests.each_value do |request|
          source_files
            .select {|path, file| request.target.possible_source_file?(path) }
            .each do |path, file|
            (changes[path] ||= []).prepend(ContentChange.string(file.content))
          end
        end

        changes.each do |path, changes|
          target = project.target_for_source_path(path)

          if target
            file = source_files[path] || SourceFile.no_data(path: path, content: "")
            content = changes.inject(file.content) {|text, change| change.apply_to(text) }
            source_files[path] = file.update_content(content)
            requests[target].source_paths << path
          end
        end
      end

      def type_check_file(target:, subtyping:, path:, text:)
        Steep.logger.tagged "#type_check_file(#{path}@#{target.name})" do
          source = Source.parse(text, path: path, factory: subtyping.factory)
          typing = TypeCheckService.type_check(source: source, subtyping: subtyping, constant_resolver: yield)
          SourceFile.with_typing(path: path, content: text, node: source.node, typing: typing)
        end
      rescue AnnotationParser::SyntaxError => exn
        error = Diagnostic::Ruby::SyntaxError.new(message: exn.message, location: exn.location)
        SourceFile.with_syntax_error(path: path, content: text, error: error)
      rescue ::Parser::SyntaxError => exn
        error = Diagnostic::Ruby::SyntaxError.new(message: exn.message, location: exn.diagnostic.location)
        SourceFile.with_syntax_error(path: path, content: text, error: error)
      rescue EncodingError => exn
        SourceFile.no_data(path: path, content: "")
      rescue RuntimeError => exn
        Steep.log_error(exn)
        SourceFile.no_data(path: path, content: text)
      end

      def self.type_check(source:, subtyping:, constant_resolver:)
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

        typing = Typing.new(source: source, root_context: context)

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
        if source_files.key?(path)
          project.target_for_source_path(path)
        end
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
