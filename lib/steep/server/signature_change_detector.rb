module Steep
  module Server
    class SignatureChangeDetector
      class Source
        attr_reader :kind
        attr_reader :content
        attr_reader :fingerprint
        attr_reader :pending_content

        def initialize(kind, content)
          @kind = kind
          @content = content
          @fingerprint = Source.fingerprint(kind, content)
          @pending_content = nil
        end

        def push(content)
          @pending_content = content
        end

        def updated?
          content = pending_content or return false
          @pending_content = nil
          return false if content == self.content

          @content = content
          new_fingerprint = Source.fingerprint(kind, content)

          # The declarations stay what they were while the RBS file cannot be parsed
          return false unless new_fingerprint

          (new_fingerprint != fingerprint).tap do
            @fingerprint = new_fingerprint
          end
        end

        def self.fingerprint(kind, content)
          # The parsers take UTF-8 only, as the environments do
          return unless content.valid_encoding?

          case kind
          when :rbs
            buffer = RBS::Buffer.new(name: Pathname("a.rbs"), content: content)
            _, directives, decls = RBS::Parser.parse_signature(buffer)
            [directives.map { directive_fingerprint(_1) }, decls, decls.map { annotations_fingerprint(_1) }]
          when :inline
            buffer = RBS::Buffer.new(name: Pathname("a.rb"), content: content)
            RBS::InlineParser.parse(buffer, Prism.parse(content)).type_fingerprint
          end
        rescue RBS::ParsingError
          nil
        end

        def self.directive_fingerprint(directive)
          case directive
          when RBS::AST::Directives::Use
            directive.clauses.map do |clause|
              case clause
              when RBS::AST::Directives::Use::SingleClause
                [clause.type_name.to_s, clause.new_name&.to_s]
              when RBS::AST::Directives::Use::WildcardClause
                clause.namespace.to_s
              end
            end
          when RBS::AST::Directives::ResolveTypeNames
            directive.value
          end
        end

        def self.annotations_fingerprint(decl)
          case decl
          when RBS::AST::Declarations::Class, RBS::AST::Declarations::Module, RBS::AST::Declarations::Interface
            [decl.annotations.map(&:string), decl.members.map { member_annotations_fingerprint(_1) }]
          when RBS::AST::Declarations::TypeAlias, RBS::AST::Declarations::Constant, RBS::AST::Declarations::Global
            decl.annotations.map(&:string)
          else
            []
          end
        end

        def self.member_annotations_fingerprint(member)
          case member
          when RBS::AST::Declarations::Base
            annotations_fingerprint(member)
          when RBS::AST::Members::MethodDefinition, RBS::AST::Members::Include, RBS::AST::Members::Extend, RBS::AST::Members::Prepend,
               RBS::AST::Members::AttrReader, RBS::AST::Members::AttrWriter, RBS::AST::Members::AttrAccessor, RBS::AST::Members::Alias
            member.annotations.map(&:string)
          else
            []
          end
        end
      end

      attr_reader :sources

      def initialize
        @sources = {}
      end

      def add_source(path, content, kind:)
        sources[path] = Source.new(kind, content)
      end

      def push(path, content, kind:)
        (sources[path] ||= Source.new(kind, "")).push(content)
      end

      def has_source?(path)
        sources.key?(path)
      end

      def updated_paths
        sources.each.with_object(Set[]) do |(path, source), set| #$ Set[Pathname]
          set << path if source.updated?
        end
      end
    end
  end
end
