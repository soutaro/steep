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
            alias_decl = service.latest_env.type_alias_decls[head.name]&.decl or raise

            TypeAliasContent.new(
              location: head.location || raise,
              decl: alias_decl
            )
          when ::RBS::Types::ClassInstance, ::RBS::Types::ClassSingleton
            if loc_key == :name
              location = head.location&.[](:name) or raise

              class_entry = service.latest_env.module_class_entry(head.name) or raise
              case class_entry
              when ::RBS::Environment::ClassEntry, ::RBS::Environment::ModuleEntry
                class_decl = class_entry.primary.decl
              when ::RBS::Environment::ClassAliasEntry, ::RBS::Environment::ModuleAliasEntry
                class_decl = class_entry.decl
              end

              ClassContent.new(
                location: location,
                decl: class_decl
              )
            end
          when ::RBS::Types::Interface
            env = service.latest_env
            interface_decl = env.interface_decls[head.name]&.decl or raise
            location = head.location&.[](:name) or raise

            InterfaceContent.new(
              location: location,
              decl: interface_decl
            )
          when ::RBS::AST::Declarations::ClassAlias, ::RBS::AST::Declarations::ModuleAlias
            if loc_key == :old_name
              location = head.location&.[](:old_name) or raise

              class_entry = service.latest_env.module_class_entry(head.old_name) or raise
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
end
