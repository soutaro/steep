module Steep
  class Project
    class SignatureFile
      attr_reader :path
      attr_reader :content
      attr_reader :content_updated_at

      attr_reader :status

      ParseErrorStatus = Struct.new(:error, :timestamp, keyword_init: true)
      DeclarationsStatus = Struct.new(:declarations, :timestamp, keyword_init: true)

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
        buffer = RBS::Buffer.new(name: path, content: content)
        decls = RBS::Parser.parse_signature(buffer)
        @status = DeclarationsStatus.new(declarations: decls, timestamp: Time.now)
      rescue RBS::Parser::SyntaxError, RBS::Parser::SemanticsError => exn
        @status = ParseErrorStatus.new(error: exn, timestamp: Time.now)
      end
    end
  end
end
