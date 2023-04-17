module Steep
  module Services
    module HoverProvider
      class RBS
        TypeAliasContent = _ = Struct.new(:location, :decl, keyword_init: true)
        ClassContent = _ = Struct.new(:location, :decl, keyword_init: true)
        InterfaceContent = _ = Struct.new(:location, :decl, keyword_init: true)

        attr_reader :service

        def initialize(service:)
          @service = service
        end

        def project
          service.project
        end

        def content_for(target:, path:, line:, column:)
          service = self.service.signature_services[target.name]

          env = service.latest_env
          buffer = env.buffers.find {|buf| buf.name.to_s == path.to_s } or return
          (dirs, decls = env.signatures[buffer]) or raise

          locator = ::RBS::Locator.new(buffer: buffer, dirs: dirs, decls: decls)
          loc_key, path = locator.find2(line: line, column: column) || return
          head, *_tail = path

          case head
          when ::RBS::Types::Alias
            content_for_type_name(head.name, env: env, location: head.location || raise)

          when ::RBS::Types::ClassInstance, ::RBS::Types::ClassSingleton
            if loc_key == :name
              location = head.location&.[](:name) or raise
              content_for_type_name(head.name, env: env, location: location)
            end

          when ::RBS::Types::Interface
            location = head.location&.[](:name) or raise
            content_for_type_name(head.name, env: env, location: location)

          when ::RBS::AST::Declarations::ClassAlias, ::RBS::AST::Declarations::ModuleAlias
            if loc_key == :old_name
              location = head.location&.[](:old_name) or raise
              content_for_type_name(head.old_name, env: env, location: location)
            end

          when ::RBS::AST::Directives::Use::SingleClause
            if loc_key == :type_name
              location = head.location&.[](:type_name) or raise
              content_for_type_name(head.type_name.absolute!, env: env, location: location)
            end

          when ::RBS::AST::Directives::Use::WildcardClause
            if loc_key == :namespace
              location = head.location&.[](:namespace) or raise
              content_for_type_name(head.namespace.to_type_name.absolute!, env: env, location: location)
            end
          end
        end

        def content_for_type_name(type_name, env:, location:)
          case
          when type_name.alias?
            alias_decl = env.type_alias_decls[type_name]&.decl or return
            TypeAliasContent.new(location: location, decl: alias_decl)
          when type_name.interface?
            interface_decl = env.interface_decls[type_name]&.decl or return
            InterfaceContent.new(location: location, decl: interface_decl)
          when type_name.class?
            class_entry = env.module_class_entry(type_name) or return

            case class_entry
            when ::RBS::Environment::ClassEntry, ::RBS::Environment::ModuleEntry
              class_decl = class_entry.primary.decl
            when ::RBS::Environment::ClassAliasEntry, ::RBS::Environment::ModuleAliasEntry
              class_decl = class_entry.decl
            end

            ClassContent.new(location: location, decl: class_decl)
          end
        end
      end
    end
  end
end
