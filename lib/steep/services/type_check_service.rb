module Steep
  module Services
    class TypeCheckService
      attr_reader :project
      attr_reader :signature_files
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

        # RBS type names referenced while type-checking this file (see TypeNameReferences).
        attr_reader :referenced_type_names

        # True when the cached `typing`/`referenced_type_names` predate the
        # current `content` and must be recomputed before being reused.
        attr_reader :outdated

        # True when the last check left a reference unresolved (e.g. an unknown
        # constant). Such a reference is absent from `referenced_type_names`, so a
        # type added later would not intersect it; while set, the file is
        # re-checked on every type change until the reference resolves. This keeps
        # rbs-inline sound, where a `.rb` is checked before its generated `.rbs`.
        attr_reader :has_unresolved_references

        def initialize(path:, node:, content:, typing:, ignores:, errors:, referenced_type_names: Set[], outdated: false, has_unresolved_references: false)
          @path = path
          @node = node
          @content = content
          @typing = typing
          @ignores = ignores
          @errors = errors
          @referenced_type_names = referenced_type_names
          @outdated = outdated
          @has_unresolved_references = has_unresolved_references
        end

        def self.with_syntax_error(path:, content:, error:)
          new(path: path, node: false, content: content, errors: [error], typing: nil, ignores: nil)
        end

        def self.with_typing(path:, content:, typing:, node:, ignores:, referenced_type_names: Set[], has_unresolved_references: false)
          new(path: path, node: node, content: content, errors: nil, typing: typing, ignores: ignores, referenced_type_names: referenced_type_names, has_unresolved_references: has_unresolved_references)
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
            ignores: ignores,
            referenced_type_names: referenced_type_names,
            has_unresolved_references: has_unresolved_references,
            outdated: true
          )
        end

        # Flags the cached result as stale (a referenced type changed). Sticky
        # until the file is re-checked, so a deferred re-check is never lost.
        def mark_outdated!
          @outdated = true
          self
        end

        def diagnostics
          case
          when errors
            errors
          when typing && ignores
            errors = [] #: Array[Diagnostic::Ruby::Base]
            error_lines = [] #: Array[Integer]

            used_comments = Set[].compare_by_identity #: Set[Source::IgnoreRanges::ignore]

            typing.errors.each do |diagnostic|
              case diagnostic.location
              when ::Parser::Source::Range
                error_lines |= (diagnostic.location.first_line..diagnostic.location.last_line).to_a
                if ignore = ignores.ignore?(diagnostic.location.first_line, diagnostic.location.last_line, diagnostic.diagnostic_code)
                  used_comments << ignore
                  next
                end
              when RBS::Location
                if ignore = ignores.ignore?(diagnostic.location.start_line, diagnostic.location.end_line, diagnostic.diagnostic_code)
                  used_comments << ignore
                  next
                end
              end

              errors << diagnostic
            end

            ignores.each_ignore do |ignore|
              next if used_comments.include?(ignore)

              case ignore
              when Array
                location = RBS::Location.new(ignore[0].location.buffer, ignore[0].location.start_pos, ignore[1].location.end_pos)
              else
                location = ignore.location
              end

              errors << Diagnostic::Ruby::RedundantIgnoreComment.new(location: location)
            end

            ignores.error_ignores.each do |ignore|
              errors << Diagnostic::Ruby::InvalidIgnoreComment.new(comment: ignore.comment)
            end

            errors
          else
            []
          end
        end
      end

      # Per-file validation state for a signature file (`.rbs`, or `.rb` with
      # inline RBS) in one target: the signature-side analogue of `SourceFile`
      # for incremental skipping. Stores diagnostics directly, since validation
      # has no `Typing`-like result to derive them from on demand.
      class SignatureFile
        attr_reader :diagnostics

        # Type names touched while validating this file (cf. SourceFile#referenced_type_names).
        attr_reader :referenced_type_names

        # True when a referenced type changed after validation; sticky until the
        # file is re-validated, so a deferred re-validation is never lost.
        attr_reader :outdated

        def initialize(diagnostics:, referenced_type_names:, outdated: false)
          @diagnostics = diagnostics
          @referenced_type_names = referenced_type_names
          @outdated = outdated
        end

        def mark_outdated!
          @outdated = true
          self
        end
      end

      def initialize(project:)
        @project = project

        @source_files = {}
        @signature_services = project.targets.each.with_object({}) do |target, hash| #$ Hash[Symbol, SignatureService]
          loader = Project::Target.construct_env_loader(options: target.options, project: project)
          hash[target.name] = SignatureService.load_from(loader, implicitly_returns_nil: target.implicitly_returns_nil)
        end
        # Cached SignatureFile per target then path (a signature is validated per target).
        @signature_files = project.targets.each.with_object({}) do |target, hash| #$ Hash[Symbol, Hash[Pathname, SignatureFile]]
          hash[target.name] = {}
        end
      end

      def signature_diagnostics
        # @type var signature_diagnostics: Hash[Pathname, Array[Diagnostic::Signature::Base]]
        signature_diagnostics = {}

        project.targets.each do |target|
          service = signature_services.fetch(target.name)

          service.each_rbs_path do |path|
            signature_diagnostics[path] ||= []
          end

          case service.status
          when SignatureService::SyntaxErrorStatus, SignatureService::AncestorErrorStatus
            service.status.diagnostics.group_by {|diag| diag.location&.buffer&.name&.to_s }.each do |path_string, diagnostics|
              if path_string
                path = Pathname(path_string)
                signature_diagnostics.fetch(path).push(*diagnostics)
              end
            end
          when SignatureService::LoadedStatus
            files = signature_files[target.name] || {}
            files.each do |path, file|
              signature_diagnostics.fetch(path).push(*file.diagnostics)
            end
          end
        end

        signature_diagnostics
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
        # Each target's changed-name set describes only this update; clear stale ones.
        signature_services.each_value(&:reset_last_changed_type_names)

        Steep.measure "#update_signature" do
          update_signature(changes: changes)
        end

        Steep.measure "#update_sources" do
          update_sources(changes: changes)
        end

        invalidate_outdated_source_files()
        invalidate_outdated_signature_files()
      end

      # Marks each cached source file whose referenced types intersect this
      # update's changed names as outdated. Recorded on the file (not per job) so
      # a re-check deferred to a later cycle is not lost when changed_names moves on.
      def invalidate_outdated_source_files
        source_files.each_value do |file|
          next if file.outdated
          next unless file.typing

          target = project.target_for_source_path(file.path) || project.target_for_inline_source_path(file.path)
          next unless target

          # target is a project target, so the service always exists.
          signature_service = signature_services.fetch(target.name)

          changed_names = signature_service.last_changed_type_names
          next if changed_names.empty?

          if file.referenced_type_names.intersect?(changed_names)
            file.mark_outdated!
          end
        end
      end

      # Signature-side counterpart of #invalidate_outdated_source_files. A file's
      # own edit is covered too: its defined names are part of both sets.
      def invalidate_outdated_signature_files
        signature_files.each do |target_name, files_by_path|
          # signature_files and signature_services share their target-name keys.
          signature_service = signature_services.fetch(target_name)
          changed_names = signature_service.last_changed_type_names
          next if changed_names.empty?

          files_by_path.each_value do |file|
            next if file.outdated
            file.mark_outdated! if file.referenced_type_names.intersect?(changed_names)
          end
        end
      end

      def signature_validation_needed?(path:, target:)
        service = signature_services.fetch(target.name)
        return true unless service.status.is_a?(SignatureService::LoadedStatus)
        file = signature_files.fetch(target.name)[path]
        return true unless file
        file.outdated
      end

      # Validates the signature file, reusing the cached diagnostics when nothing
      # it references changed (see #signature_validation_needed?).
      def validate_signature(path:, target:)
        unless signature_validation_needed?(path: path, target: target)
          Steep.logger.debug { "Skipping signature validation for #{path} (no referenced type changed)" }
          return signature_files.fetch(target.name).fetch(path).diagnostics
        end

        Steep.logger.tagged "#validate_signature(path=#{path})" do
          Steep.measure "validation" do
            service = signature_services.fetch(target.name)

            unless target.possible_signature_file?(path) || target.possible_inline_source_file?(path) || service.env_rbs_paths.include?(path)
              raise "#{path} is not library nor signature of #{target.name}"
            end

            # Refs only matter for a healthy env; an error status always re-validates.
            referenced_type_names = Set[] #: Set[RBS::TypeName]

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

              # Own defined types plus what the validator referenced; defined names
              # let ancestor changes reach us via the descendant closure.
              referenced_type_names = Set.new(type_names)
              referenced_type_names.merge(validator.referenced_type_names)
            end

            source = service.status.files[path]
            if source.is_a?(RBS::Source::Ruby)
              source.diagnostics.each do |d|
                diagnostic = Diagnostic::Signature::InlineDiagnostic.new(d)
                diagnostics.push(diagnostic)
              end
            end

            signature_files.fetch(target.name)[path] =
              SignatureFile.new(diagnostics: diagnostics, referenced_type_names: referenced_type_names)
            diagnostics
          end
        end
      end

      def type_check_needed?(path:, target:)
        file = source_files[path]
        return true unless file&.typing
        return true if file.outdated
        # Incomplete refs (an unresolved reference): can't trust the intersection.
        return true if file.has_unresolved_references

        # target is a project target, so the service always exists.
        signature_service = signature_services.fetch(target.name)
        return true unless signature_service.current_subtyping

        false
      end

      # Type checks the source file and returns its diagnostics (nil if it can't
      # run), reusing the cached result when nothing it references changed (see
      # #type_check_needed?).
      def typecheck_source(path:, target:)
        return unless target

        unless type_check_needed?(path: path, target: target)
          Steep.logger.debug { "Skipping type check for #{path} (no referenced type changed)" }
          return source_files.fetch(path).diagnostics
        end

        Steep.logger.tagged "#typecheck_source(path=#{path})" do
          Steep.measure "typecheck" do
            signature_service = signature_services.fetch(target.name)
            subtyping = signature_service.current_subtyping

            if subtyping
              text = source_files.fetch(path).content
              file = type_check_file(target: target, subtyping: subtyping, path: path, text: text) { signature_service.latest_constant_resolver }
              source_files[path] = file

              file.diagnostics
            else
              # Signature loading failed. If the errors originate from library RBS files,
              # they won't be reported by validate_signature (which filters by user file path).
              # Report them on source files so the user knows type checking is broken. (#2176)
              case signature_service.status
              when SignatureService::SyntaxErrorStatus, SignatureService::AncestorErrorStatus
                library_errors = signature_service.status.diagnostics.select do |diag|
                  diag_path = diag.location && Pathname(diag.location.buffer.name)
                  diag_path &&
                    signature_service.env_rbs_paths.include?(diag_path) &&
                    !signature_service.status.files.key?(diag_path)
                end

                unless library_errors.empty?
                  text = source_files.fetch(path).content
                  buffer = RBS::Buffer.new(name: path, content: text)
                  location = RBS::Location.new(buffer: buffer, start_pos: 0, end_pos: text.size)

                  library_errors.map do |error|
                    Diagnostic::Ruby::LibraryRBSError.new(error: error, location: location)
                  end
                end
              end
            end
          end
        end
      end

      def update_signature(changes:)
        Steep.logger.tagged "#update_signature" do
          signature_targets = {} #: Hash[Pathname, Project::Target]
          changes.each do |path, changes|
            if target = project.target_for_signature_path(path) || project.target_for_inline_source_path(path)
              signature_targets[path] = target
            end
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
          referenced_type_names = TypeNameReferences.from_source_file(typing: typing, source: source)
          # An unknown constant leaves no entry in referenced_type_names; flag the
          # set as incomplete (see SourceFile#has_unresolved_references).
          has_unresolved_references = typing.errors.any? { |error| error.is_a?(Diagnostic::Ruby::UnknownConstant) }
          SourceFile.with_typing(path: path, content: text, node: source.node, typing: typing, ignores: ignores, referenced_type_names: referenced_type_names, has_unresolved_references: has_unresolved_references)
        end
      rescue AnnotationParser::SyntaxError => exn
        error = Diagnostic::Ruby::AnnotationSyntaxError.new(message: exn.message, location: exn.location)
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

        case annotations.self_type
        when AST::Types::Name::Instance
          module_name = annotations.self_type.name
          module_type = AST::Types::Name::Singleton.new(name: module_name)
          instance_type = annotations.self_type
        when AST::Types::Name::Singleton
          module_name = annotations.self_type.name
          module_type = annotations.self_type
          instance_type = annotations.self_type
        else
          module_name = AST::Builtin::Object.module_name
          module_type = AST::Builtin::Object.module_type
          instance_type = AST::Builtin::Object.instance_type
        end

        definition = subtyping.factory.definition_builder.build_instance(module_name)

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
            instance_type: instance_type,
            module_type: module_type,
            implement_name: nil,
            nesting: nil,
            class_name: module_name,
            instance_definition: subtyping.factory.definition_builder.build_instance(module_name),
            module_definition: subtyping.factory.definition_builder.build_singleton(module_name)
          ),
          method_context: nil,
          break_context: nil,
          self_type: instance_type,
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
        return true if source_files.key?(path)
        return true if project.target_for_source_path(path)
        return true if project.target_for_inline_source_path(path)
        false
      end

      def signature_file?(path)
        relative_path = project.relative_path(path)
        targets = signature_services.select {|_, sig| sig.files.key?(relative_path) || sig.env_rbs_paths.include?(path) }
        unless targets.empty?
          targets.keys
        end
      end
    end
  end
end
