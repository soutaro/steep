module Steep
  module Services
    module HoverProvider
      module SingletonMethods
        def content_for(service:, path:, line:, column:)
          project = service.project

          case
          when target = project.target_for_source_path(path)
            Ruby.new(service: service).content_for(target: target, path: path, line: line, column: column)
          when target = project.target_for_signature_path(path)
            RBS.new(service: service).content_for(target: target, path: path, line: line, column: column)
          end
        end
      end

      extend SingletonMethods
    end
  end
end
