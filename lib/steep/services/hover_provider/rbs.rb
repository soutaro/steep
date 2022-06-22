module Steep
  module Services
    module HoverProvider
      class RBS
        TypeAliasContent = Struct.new(:location, :decl, keyword_init: true)
        ClassContent = Struct.new(:location, :decl, keyword_init: true)
        InterfaceContent = Struct.new(:location, :decl, keyword_init: true)

        attr_reader :service

        def initialize(service:)
          @service = service
        end

        def project
          service.project
        end

        def content_for(target:, path:, line:, column:)
          service = self.service.signature_services[target.name]

          _, decls = service.latest_env.buffers_decls.find do |buffer, _|
            Pathname(buffer.name) == path
          end

          return if decls.nil?

          loc_key, path = ::RBS::Locator.new(decls: decls).find2(line: line, column: column) || return
          head, *_tail = path

          case head
          when ::RBS::Types::Alias
            alias_decl = service.latest_env.alias_decls[head.name]&.decl or raise

            TypeAliasContent.new(
              location: head.location,
              decl: alias_decl
            )
          when ::RBS::Types::ClassInstance, ::RBS::Types::ClassSingleton
            if loc_key == :name
              env = service.latest_env
              class_decl = env.class_decls[head.name]&.decls[0]&.decl or raise
              location = head.location[:name]
              ClassContent.new(
                location: location,
                decl: class_decl
              )
            end
          when ::RBS::Types::Interface
            env = service.latest_env
            interface_decl = env.interface_decls[head.name]&.decl or raise
            location = head.location[:name]

            InterfaceContent.new(
              location: location,
              decl: interface_decl
            )
          end
        end
      end
    end
  end
end
