module Steep
  class Project
    class SourceFile
      attr_reader :options
      attr_reader :path
      attr_reader :content
      attr_reader :content_updated_at
      attr_reader :factory

      attr_reader :source
      attr_reader :typing
      attr_reader :last_type_checked_at

      def initialize(path:, options:)
        @path = path
        @options = options
        self.content = ""
      end

      def content=(content)
        @content_updated_at = Time.now
        @content = content
      end

      def requires_type_check?
        if last = last_type_checked_at
          last < content_updated_at
        else
          true
        end
      end

      def invalidate
        @source = nil
        @typing = nil
        @last_type_checked_at = nil
      end

      def parse(factory:)
        _ = @source =
          begin
            Source.parse(content, path: path.to_s, factory: factory, labeling: ASTUtils::Labeling.new)
          rescue ::Parser::SyntaxError => exn
            Steep.logger.warn { "Syntax error on #{path}: #{exn.inspect}" }
            exn
          rescue EncodingError => exn
            Steep.logger.warn { "Encoding error on #{path}: #{exn.inspect}" }
            exn
          end
      end

      def errors
        typing&.errors&.reject do |error|
          case
          when error.is_a?(Errors::FallbackAny)
            !options.fallback_any_is_error
          when error.is_a?(Errors::MethodDefinitionMissing)
            options.allow_missing_definitions
          end
        end
      end

      def type_check(check)
        case source = self.source
        when Source
          @typing = Typing.new

          annotations = source.annotations(block: source.node, factory: check.factory, current_module: AST::Namespace.root)

          const_env = TypeInference::ConstantEnv.new(factory: check.factory, context: nil)
          type_env = TypeInference::TypeEnv.build(annotations: annotations,
                                                  subtyping: check,
                                                  const_env: const_env,
                                                  signatures: check.factory.env)

          construction = TypeConstruction.new(
            checker: check,
            annotations: annotations,
            source: source,
            self_type: AST::Builtin::Object.instance_type,
            block_context: nil,
            module_context: TypeConstruction::ModuleContext.new(
              instance_type: nil,
              module_type: nil,
              implement_name: nil,
              current_namespace: AST::Namespace.root,
              const_env: const_env,
              class_name: nil
            ),
            method_context: nil,
            typing: typing,
            break_context: nil,
            type_env: type_env
          )

          construction.synthesize(source.node)

          @last_type_checked_at = Time.now
        end
      end
    end

    class SignatureFile
      attr_reader :path
      attr_reader :content
      attr_reader :content_updated_at

      def initialize(path:)
        @path = path
        self.content = ""
      end

      def parse()
        buffer = Ruby::Signature::Buffer.new(name: path, content: content)
        [Ruby::Signature::Parser.parse_signature(buffer), buffer]
      end

      def content=(content)
        @content_updated_at = Time.now
        @content = content
      end
    end
  end
end
