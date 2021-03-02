module Steep
  module Services
    class TypeCheckService
      attr_reader :project
      attr_reader :assignment
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

      def initialize(project:, assignment:)
        @project = project
        @assignment = assignment

        @signature_validation_diagnostics = {}
        @source_files = {}
        @signature_services = project.targets.each.with_object({}) do |target, hash|
          loader = Project::Target.construct_env_loader(options: target.options)
          hash[target.name] = SignatureService.load_from(loader)
        end

        @no_type_checking = false
      end

      def no_type_checking!
        @no_type_checking = true
        self
      end

      def no_type_checking?
        @no_type_checking
      end

      def signature_diagnostics
        signature_diagnostics = {}

        project.targets.each do |target|
          service = signature_services[target.name]

          service.each_rbs_path do |path|
            if assignment =~ path
              signature_diagnostics[path] ||= []
            end
          end

          case service.status
          when SignatureService::SyntaxErrorStatus, SignatureService::AncestorErrorStatus
            service.status.diagnostics.group_by {|diag| Pathname(diag.location.buffer.name) }.each do |path, diagnostics|
              if assignment =~ path
                signature_diagnostics[path].push(*diagnostics)
              end
            end
          when SignatureService::LoadedStatus
            validation_diagnostics = signature_validation_diagnostics[target.name] || {}
            validation_diagnostics.each do |path, diagnostics|
              if assignment =~ path
                signature_diagnostics[path].push(*diagnostics)
              end
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

      def update(changes:, &block)
        updated_targets = Steep.measure "Updating signatures..." do
          update_signature(changes: changes, &block)
        end
        project.targets.each do |target|
          Steep.measure "Typechecking target `#{target.name}`..." do
            update_target(target: target, changes: changes, updated: updated_targets.include?(target), &block)
          end
        end
      end

      def update_signature(changes:, &block)
        updated_targets = []

        project.targets.each do |target|
          signature_service = signature_services[target.name]
          signature_changes = changes.filter {|path, _| target.possible_signature_file?(path) }

          unless signature_changes.empty?
            updated_targets << target
            signature_service.update(signature_changes)
          end
        end

        accumulated_diagnostics = {}

        updated_targets.each do |target|
          service = signature_services[target.name]

          next if no_type_checking?

          case service.status
          when SignatureService::SyntaxErrorStatus, SignatureService::AncestorErrorStatus
            service.status.diagnostics.group_by {|diag| Pathname(diag.location.buffer.name) }.each do |path, diagnostics|
              if assignment =~ path
                array = accumulated_diagnostics[path] ||= []
                array.push(*diagnostics)
                yield [path, array]
              end
            end
          when SignatureService::LoadedStatus
            validator = Signature::Validator.new(checker: service.current_subtyping)
            paths = service.each_rbs_path.select {|path| assignment =~ path }.to_set
            type_names = service.type_names(paths: paths, env: service.latest_env)

            validated_names = Set[]
            type_names.each do |type_name|
              unless validated_names.include?(type_name)
                case
                when type_name.class?
                  validator.validate_one_class(type_name)
                when type_name.interface?
                  validator.validate_one_interface(type_name)
                when type_name.alias?
                  validator.validate_one_alias(type_name)
                end

                validated_names << type_name
              end
            end

            validator.validate_const()
            validator.validate_global()

            target_diagnostics = validator.each_error.group_by {|error| Pathname(error.location.buffer.name) }
            signature_validation_diagnostics[target.name] = target_diagnostics

            paths.each do |path|
              array = (accumulated_diagnostics[path] ||= [])
              if ds = target_diagnostics[path]
                array.push(*ds)
              end
              yield [path, array]
            end
          end
        end

        updated_targets
      end

      def update_target(changes:, target:, updated:, &block)
        contents = {}

        if updated
          source_files.each do |path, file|
            if target.possible_source_file?(path)
              contents[path] = file.content
            end
          end

          changes.each do |path, changes|
            if target.possible_source_file?(path)
              text = contents[path] || ""
              contents[path] = changes.inject(text) {|text, change| change.apply_to(text) }
            end
          end
        else
          changes.each do |path, changes|
            if target.possible_source_file?(path)
              text = source_files[path]&.content || ""
              contents[path] = changes.inject(text) {|text, change| change.apply_to(text) }
            end
          end
        end

        signature_service = signature_services[target.name]
        subtyping = signature_service.current_subtyping

        contents.each do |path, text|
          if assignment =~ path
            if subtyping
              file = type_check_file(target: target, subtyping: subtyping, path: path, text: text)
              yield [file.path, file.diagnostics]
            else
              if source_files.key?(path)
                file = source_files[path]&.update_content(text)
              else
                file = SourceFile.no_data(path: path, content: text)
                yield [file.path, []]
              end
            end

            source_files[path] = file
          end
        end
      end

      def type_check_file(target:, subtyping:, path:, text:)
        Steep.logger.tagged "#type_check_file(#{path}@#{target.name})" do
          source = Source.parse(text, path: path, factory: subtyping.factory)
          if no_type_checking?
            SourceFile.no_data(path: path, content: text)
          else
            typing = TypeCheckService.type_check(source: source, subtyping: subtyping)
            SourceFile.with_typing(path: path, content: text, node: source.node, typing: typing)
          end
        end
      rescue AnnotationParser::SyntaxError => exn
        SourceFile.no_data(path: path, content: text)
        # SourceFile.with_syntax_error(path: path, content: text, error: exn)
      rescue ::Parser::SyntaxError, EncodingError => exn
        SourceFile.no_data(path: path, content: text)
        # SourceFile.with_syntax_error(path: path, content: text, error: exn)
      end

      def self.type_check(source:, subtyping:)
        annotations = source.annotations(block: source.node, factory: subtyping.factory, current_module: RBS::Namespace.root)
        const_env = TypeInference::ConstantEnv.new(factory: subtyping.factory, context: [RBS::Namespace.root])
        type_env = TypeInference::TypeEnv.build(annotations: annotations,
                                                subtyping: subtyping,
                                                const_env: const_env,
                                                signatures: subtyping.factory.env)
        lvar_env = TypeInference::LocalVariableTypeEnv.empty(
          subtyping: subtyping,
          self_type: AST::Builtin::Object.instance_type
        ).annotate(annotations)

        context = TypeInference::Context.new(
          block_context: nil,
          module_context: TypeInference::Context::ModuleContext.new(
            instance_type: AST::Builtin::Object.instance_type,
            module_type: AST::Builtin::Object.module_type,
            implement_name: nil,
            current_namespace: RBS::Namespace.root,
            const_env: const_env,
            class_name: AST::Builtin::Object.module_name,
            instance_definition: subtyping.factory.definition_builder.build_instance(AST::Builtin::Object.module_name),
            module_definition: subtyping.factory.definition_builder.build_singleton(AST::Builtin::Object.module_name)
          ),
          method_context: nil,
          break_context: nil,
          self_type: AST::Builtin::Object.instance_type,
          type_env: type_env,
          lvar_env: lvar_env,
          call_context: TypeInference::MethodCall::TopLevelContext.new
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
    end
  end
end
