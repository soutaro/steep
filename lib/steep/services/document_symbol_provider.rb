module Steep
  module Services
    class DocumentSymbolProvider

      LSP = LanguageServer::Protocol

      attr_reader :service

      def initialize(service:)
        @service = service
      end

      def content_for(path:)
        project = service.project

        target = project.targets_for_path(path)
        case target
        when Project::Target
          nil
        when Array
          signature_service = service.signature_services[target[0].name]
          env = signature_service.latest_env
          buffer = env.buffers.find {|buf| buf.name.to_s == path.to_s } or return
          (_dirs, decls = env.signatures[buffer]) or raise

          # @type var document_symbols: Array[LSP::Interface::DocumentSymbol]
          document_symbols = []
          decls.each_with_object(document_symbols) do |decl, buffer|
            build_document_symbols(decl, buffer)
          end
        end
      end

      def build_document_symbols(node, buffer, top_level: true)
        case node
        when ::RBS::AST::Declarations::Class, ::RBS::AST::Declarations::Module, ::RBS::AST::Declarations::Interface
          range = build_range(node.location)
          name = symbol_name_with_type_params(node, top_level: top_level)
          kind = kind_from_ast_node(node)
          children = node.members.each_with_object([]) do |member, children_buffer|
            build_document_symbols(member, children_buffer, top_level: false)
          end
          document_symbol = LSP::Interface::DocumentSymbol.new(name: name, kind: kind, range: range, selection_range: range, children: children)
          buffer << document_symbol
        when ::RBS::AST::Declarations::TypeAlias
          range = build_range(node.location)
          name = symbol_name_with_type_params(node, top_level: top_level)
          kind = kind_from_ast_node(node)
          document_symbol = LSP::Interface::DocumentSymbol.new(name: name, kind: kind, range: range, selection_range: range)
          buffer << document_symbol
        when ::RBS::AST::Declarations::Constant
          range = build_range(node.location)
          name = trim_namespace_scope(node.name.to_s, top_level: top_level)
          kind = kind_from_ast_node(node)
          document_symbol = LSP::Interface::DocumentSymbol.new(name: name, kind: kind, range: range, selection_range: range)
          buffer << document_symbol
        when ::RBS::AST::Declarations::ClassAlias, ::RBS::AST::Declarations::ModuleAlias
          range = build_range(node.location)
          name = trim_namespace_scope(node.new_name.to_s, top_level: false) + " = " + node.old_name.to_s
          kind = kind_from_ast_node(node)
          document_symbol = LSP::Interface::DocumentSymbol.new(name: name, kind: kind, range: range, selection_range: range)
          buffer << document_symbol
        when ::RBS::AST::Members::MethodDefinition, ::RBS::AST::Members::AttrReader, ::RBS::AST::Members::AttrWriter, ::RBS::AST::Members::AttrAccessor
          range = build_range(node.location)
          name = node.name.to_s
          kind = kind_from_ast_node(node)
          document_symbol = LSP::Interface::DocumentSymbol.new(name: name, kind: kind, range: range, selection_range: range)
          buffer << document_symbol
        when ::RBS::AST::Declarations::Global, ::RBS::AST::Members::InstanceVariable, ::RBS::AST::Members::ClassVariable, ::RBS::AST::Members::ClassInstanceVariable
          range = build_range(node.location)
          name = node.name.to_s
          kind = kind_from_ast_node(node)
          document_symbol = LSP::Interface::DocumentSymbol.new(name: name, kind: kind, range: range, selection_range: range)
          buffer << document_symbol
        when ::RBS::AST::Members::Alias
          range = build_range(node.location)
          name = "alias(#{node.new_name.to_s}, #{node.old_name.to_s})"
          kind = kind_from_ast_node(node)
          document_symbol = LSP::Interface::DocumentSymbol.new(name: name, kind: kind, range: range, selection_range: range)
          buffer << document_symbol
        when ::RBS::AST::Members::Include, ::RBS::AST::Members::Extend, ::RBS::AST::Members::Prepend
          range = build_range(node.location)
          name = "#{node.class.name.split("::").last.downcase}(#{node.name.to_s})"
          kind = kind_from_ast_node(node)
          document_symbol = LSP::Interface::DocumentSymbol.new(name: name, kind: kind, range: range, selection_range: range)
          buffer << document_symbol
        end
      end

      def build_range(location)
        raise "location is nil" unless location
        start_position = LSP::Interface::Position.new(line: location.start_line - 1, character: location.start_column)
        end_position = LSP::Interface::Position.new(line: location.end_line - 1, character: location.end_column)
        LSP::Interface::Range.new(start: start_position, end: end_position)
      end

      def kind_from_ast_node(node)
        case node
        when ::RBS::AST::Declarations::Class, ::RBS::AST::Declarations::ClassAlias, ::RBS::AST::Declarations::TypeAlias
          LSP::Constant::SymbolKind::CLASS
        when ::RBS::AST::Declarations::Module, ::RBS::AST::Declarations::ModuleAlias, ::RBS::AST::Members::Include, ::RBS::AST::Members::Extend, ::RBS::AST::Members::Prepend
          LSP::Constant::SymbolKind::MODULE
        when ::RBS::AST::Declarations::Interface
          LSP::Constant::SymbolKind::INTERFACE
        when ::RBS::AST::Members::MethodDefinition, ::RBS::AST::Members::AttrReader, ::RBS::AST::Members::AttrWriter, ::RBS::AST::Members::AttrAccessor, ::RBS::AST::Members::Alias
          LSP::Constant::SymbolKind::METHOD
        when ::RBS::AST::Declarations::Constant
          LSP::Constant::SymbolKind::CONSTANT
        when ::RBS::AST::Declarations::Global
          LSP::Constant::SymbolKind::VARIABLE
        when ::RBS::AST::Members::InstanceVariable, ::RBS::AST::Members::ClassVariable, ::RBS::AST::Members::ClassInstanceVariable
          LSP::Constant::SymbolKind::PROPERTY
        else
          raise "Unexpected node: #{node}"
        end
      end

      def trim_namespace_scope(name, top_level: true)
        if top_level
          name.start_with?("::") ? name.sub("::", "") : name
        else
          name.split("::")[-1]
        end
      end

      def symbol_name_with_type_params(decl, top_level: true)
        name = trim_namespace_scope(decl.name.to_s, top_level: top_level)
        name += "[#{decl.type_params.map(&:to_s).join(", ")}]" if decl.type_params.size > 0
        name
      end
    end
  end
end
