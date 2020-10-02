module Steep
  class Project
    class SourceFile
      attr_reader :path
      attr_reader :content
      attr_reader :content_updated_at
      attr_reader :factory

      attr_accessor :status

      ParseErrorStatus = Struct.new(:error, :timestamp, keyword_init: true)
      AnnotationSyntaxErrorStatus = Struct.new(:error, :location, :timestamp, keyword_init: true)
      TypeCheckStatus = Struct.new(:typing, :source, :timestamp, keyword_init: true)
      TypeCheckErrorStatus = Struct.new(:error, :timestamp, keyword_init: true)

      def initialize(path:)
        @path = path
        @content = false
        self.content = ""
      end

      def content=(content)
        @content_updated_at = Time.now
        @content = content
        @status = nil
      end

      def errors
        case status
        when TypeCheckStatus
          status.typing.errors
        else
          []
        end
      end

      def self.parse(source_code, path:, factory:)
        Source.parse(source_code, path: path.to_s, factory: factory, labeling: ASTUtils::Labeling.new)
      end

      def self.type_check(source, subtyping:)
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
          lvar_env: lvar_env
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

      def type_check(subtyping, env_updated_at)
        # skip type check
        return false if status && env_updated_at <= status.timestamp

        now = Time.now

        parse(subtyping.factory) do |source|
          typing = self.class.type_check(source, subtyping: subtyping)
          @status = TypeCheckStatus.new(typing: typing, source: source, timestamp: now)
        rescue RBS::NoTypeFoundError,
          RBS::NoMixinFoundError,
          RBS::NoSuperclassFoundError,
          RBS::DuplicatedMethodDefinitionError,
          RBS::InvalidTypeApplicationError => exn
          # Skip logging known signature errors (they are handled with load_signatures(validate: true))
          @status = TypeCheckErrorStatus.new(error: exn, timestamp: now)
        rescue => exn
          Steep.log_error(exn)
          @status = TypeCheckErrorStatus.new(error: exn, timestamp: now)
        end

        true
      end

      def parse(factory)
        now = Time.now

        if status.is_a?(TypeCheckStatus)
          yield status.source
        else
          yield self.class.parse(content, path: path, factory: factory)
        end
      rescue AnnotationParser::SyntaxError => exn
        Steep.logger.warn { "Annotation syntax error on #{path}: #{exn.inspect}" }
        @status = AnnotationSyntaxErrorStatus.new(error: exn, location: exn.location, timestamp: now)
      rescue ::Parser::SyntaxError, EncodingError => exn
        Steep.logger.warn { "Source parsing error on #{path}: #{exn.inspect}" }
        @status = ParseErrorStatus.new(error: exn, timestamp: now)
      end
    end
  end
end
