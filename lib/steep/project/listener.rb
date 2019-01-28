module Steep
  class Project
    class NullListener
      def parse_signature(project:, file:)
        yield
      end

      def parse_source(project:, file:)
        yield
      end

      def check(project:)
        yield
      end

      def validate_signature(project:)
        yield
      end

      def type_check_source(project:, file:)
        yield
      end

      def clear_project(project:)
        yield
      end

      def load_signature(project:)
        yield
      end
    end

    class SyntaxErrorRaisingListener < NullListener
      def load_signature(project:)
        yield.tap do
          case signature = project.signature
          when SignatureHasSyntaxError
            raise signature.errors.values[0]
          end
        end
      end

      def parse_source(project:, file:)
        yield.tap do
          case source = file.source
          when ::Parser::SyntaxError
            raise source
          end
        end
      end
    end
  end
end
