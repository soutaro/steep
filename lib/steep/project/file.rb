module Steep
  class Project
    class SourceFile
      attr_reader :path
      attr_reader :content
      attr_reader :content_updated_at
      attr_reader :factory

      attr_accessor :status

      ParseErrorStatus = Struct.new(:error, keyword_init: true)
      AnnotationSyntaxErrorStatus = Struct.new(:error, :location, keyword_init: true)
      TypeCheckStatus = Struct.new(:typing, :source, :timestamp, keyword_init: true)

      def initialize(path:)
        @path = path
        @content = false
        self.content = ""
      end

      def content=(content)
        if @content != content
          @content_updated_at = Time.now
          @content = content
          @status = nil
        end
      end

      def errors
        case status
        when TypeCheckStatus
          status.typing.errors
          # errors.reject do |error|
          #   case
          #   when error.is_a?(Errors::FallbackAny)
          #     !options.fallback_any_is_error
          #   when error.is_a?(Errors::MethodDefinitionMissing)
          #     options.allow_missing_definitions
          #   end
          # end
        else
          []
        end
      end

      def type_check(subtyping, env_updated_at)
        # skip type check
        return false if status.is_a?(TypeCheckStatus) && env_updated_at <= status.timestamp

        parse(subtyping.factory) do |source|
          typing = Typing.new

          if source
            annotations = source.annotations(block: source.node, factory: subtyping.factory, current_module: AST::Namespace.root)
            const_env = TypeInference::ConstantEnv.new(factory: subtyping.factory, context: nil)
            type_env = TypeInference::TypeEnv.build(annotations: annotations,
                                                    subtyping: subtyping,
                                                    const_env: const_env,
                                                    signatures: subtyping.factory.env)

            construction = TypeConstruction.new(
              checker: subtyping,
              annotations: annotations,
              source: source,
              self_type: AST::Builtin::Object.instance_type,
              context: TypeInference::Context.new(
                block_context: nil,
                module_context: TypeInference::Context::ModuleContext.new(
                  instance_type: nil,
                  module_type: nil,
                  implement_name: nil,
                  current_namespace: AST::Namespace.root,
                  const_env: const_env,
                  class_name: nil
                ),
                method_context: nil,
                break_context: nil
              ),
              typing: typing,
              type_env: type_env
            )

            construction.synthesize(source.node)
          end

          @status = TypeCheckStatus.new(
            typing: typing,
            source: source,
            timestamp: Time.now
          )
        end

        true
      end

      def parse(factory)
        if status.is_a?(TypeCheckStatus)
          yield status.source
        else
          yield Source.parse(content, path: path.to_s, factory: factory, labeling: ASTUtils::Labeling.new)
        end
      rescue AnnotationParser::SyntaxError => exn
        Steep.logger.warn { "Annotation syntax error on #{path}: #{exn.inspect}" }
        @status = AnnotationSyntaxErrorStatus.new(error: exn, location: exn.location)
      rescue ::Parser::SyntaxError, EncodingError => exn
        Steep.logger.warn { "Source parsing error on #{path}: #{exn.inspect}" }
        @status = ParseErrorStatus.new(error: exn)
      end
    end

    class SignatureFile
      attr_reader :path
      attr_reader :content
      attr_reader :content_updated_at

      attr_reader :status

      ParseErrorStatus = Struct.new(:error, keyword_init: true)
      DeclarationsStatus = Struct.new(:declarations, keyword_init: true)

      def initialize(path:)
        @path = path
        self.content = ""
      end

      def content=(content)
        @content_updated_at = Time.now
        @content = content
        @status = nil
      end

      def load!
        buffer = Ruby::Signature::Buffer.new(name: path, content: content)
        decls = Ruby::Signature::Parser.parse_signature(buffer)
        @status = DeclarationsStatus.new(declarations: decls)
      rescue Ruby::Signature::Parser::SyntaxError, Ruby::Signature::Parser::SemanticsError => exn
        @status = ParseErrorStatus.new(error: exn)
      end
    end
  end
end
