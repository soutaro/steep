module Steep
  module Services
    module HoverProvider
      module SingletonMethods
        def content_for(service:, path:, line:, column:)
          project = service.project
          relative_path = project.relative_path(path)

          case
          when target = project.target_for_inline_source_path(relative_path)
            ruby = Ruby.new(service: service)
            ruby.content_for_inline(target: target, path: relative_path, line: line, column: column) ||
              ruby.content_for(target: target, path: relative_path, line: line, column: column)
          when target = project.target_for_source_path(relative_path)
            Ruby.new(service: service).content_for(target: target, path: relative_path, line: line, column: column)
          when target = project.target_for_signature_path(relative_path)
            RBS.new(service: service).content_for(target: target, path: relative_path, line: line, column: column)
          when target = library_target(service, path)
            # The buffer of a library RBS file is named by its absolute path
            RBS.new(service: service).content_for(target: target, path: path, line: line, column: column)
          end
        end

        def library_target(service, path)
          target_name = service.signature_file?(path)&.first or return
          service.project.targets.find {|target| target.name == target_name }
        end
      end

      extend SingletonMethods
    end
  end
end
