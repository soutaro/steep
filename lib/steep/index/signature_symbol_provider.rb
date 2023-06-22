module Steep
  module Index
    class SignatureSymbolProvider
      LSP = LanguageServer::Protocol

      class SymbolInformation < Struct.new(:name, :kind, :container_name, :location, keyword_init: true)
      end

      attr_reader :project
      attr_reader :indexes
      attr_reader :assignment

      def initialize(project:, assignment:)
        @indexes = []
        @project = project
        @assignment = assignment
      end

      def self.test_type_name(query, type_name)
        case
        when query == ""
          true
        else
          type_name.to_s.upcase.include?(query.upcase)
        end
      end

      class <<self
        alias test_const_name test_type_name
        alias test_global_name test_type_name
      end

      def self.test_method_name(query, method_name)
        case
        when query == ""
          true
        else
          method_name.to_s.upcase.include?(query.upcase)
        end
      end

      def assigned?(path)
        if path.relative?
          if project.targets.any? {|target| target.possible_signature_file?(path) }
            path = project.absolute_path(path)
          end
        end

        assignment =~ path
      end

      def query_symbol(query)
        symbols = [] #: Array[SymbolInformation]

        indexes.each do |index|
          index.each_entry do |entry|
            case entry
            when RBSIndex::TypeEntry
              next unless SignatureSymbolProvider.test_type_name(query, entry.type_name)

              container_name = entry.type_name.namespace.relative!.to_s.delete_suffix("::")
              name = entry.type_name.name.to_s

              entry.declarations.each do |decl|
                location = decl.location or next
                next unless assigned?(Pathname(location.buffer.name))

                case decl
                when RBS::AST::Declarations::Class
                  symbols << SymbolInformation.new(
                    name: name,
                    location: location,
                    kind: LSP::Constant::SymbolKind::CLASS,
                    container_name: container_name
                  )
                when RBS::AST::Declarations::Module
                  symbols << SymbolInformation.new(
                    name: name,
                    location: location,
                    kind: LSP::Constant::SymbolKind::MODULE,
                    container_name: container_name
                  )
                when RBS::AST::Declarations::Interface
                  symbols << SymbolInformation.new(
                    name: name,
                    location: location,
                    kind: LSP::Constant::SymbolKind::INTERFACE,
                    container_name: container_name
                  )
                when RBS::AST::Declarations::TypeAlias
                  symbols << SymbolInformation.new(
                    name: name,
                    location: location,
                    kind: LSP::Constant::SymbolKind::ENUM,
                    container_name: container_name
                  )
                end
              end
            when RBSIndex::MethodEntry
              next unless SignatureSymbolProvider.test_method_name(query, entry.method_name)

              name = case entry.method_name
                     when InstanceMethodName
                       "##{entry.method_name.method_name}"
                     when SingletonMethodName
                       ".#{entry.method_name.method_name}"
                     else
                       raise
                     end
              container_name = entry.method_name.type_name.relative!.to_s

              entry.declarations.each do |decl|
                location = decl.location or next
                next unless assigned?(Pathname(location.buffer.name))

                case decl
                when RBS::AST::Members::MethodDefinition
                  symbols << SymbolInformation.new(
                    name: name,
                    location: location,
                    kind: LSP::Constant::SymbolKind::METHOD,
                    container_name: container_name
                  )
                when RBS::AST::Members::Alias
                  symbols << SymbolInformation.new(
                    name: name,
                    location: location,
                    kind: LSP::Constant::SymbolKind::METHOD,
                    container_name: container_name
                  )
                when RBS::AST::Members::AttrAccessor, RBS::AST::Members::AttrReader, RBS::AST::Members::AttrWriter
                  symbols << SymbolInformation.new(
                    name: name,
                    location: location,
                    kind: LSP::Constant::SymbolKind::PROPERTY,
                    container_name: container_name
                  )

                  if decl.ivar_name
                    symbols << SymbolInformation.new(
                      name: decl.ivar_name.to_s,
                      location: location,
                      kind: LSP::Constant::SymbolKind::FIELD,
                      container_name: container_name
                    )
                  end
                end
              end
            when RBSIndex::ConstantEntry
              next unless SignatureSymbolProvider.test_const_name(query, entry.const_name)

              entry.declarations.each do |decl|
                next unless decl.location
                next unless assigned?(Pathname(decl.location.buffer.name))

                symbols << SymbolInformation.new(
                  name: entry.const_name.name.to_s,
                  location: decl.location,
                  kind: LSP::Constant::SymbolKind::CONSTANT,
                  container_name: entry.const_name.namespace.relative!.to_s.delete_suffix("::")
                )
              end
            when RBSIndex::GlobalEntry
              next unless SignatureSymbolProvider.test_global_name(query, entry.global_name)

              entry.declarations.each do |decl|
                next unless decl.location
                next unless assigned?(Pathname(decl.location.buffer.name))

                symbols << SymbolInformation.new(
                  name: decl.name.to_s,
                  location: decl.location,
                  kind: LSP::Constant::SymbolKind::VARIABLE,
                  container_name: nil
                )
              end
            end
          end
        end

        symbols.uniq {|symbol| [symbol.name, symbol.location] }.sort_by {|symbol| symbol.name.to_s }
      end
    end
  end
end
