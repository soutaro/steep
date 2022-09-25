module Steep
  module Services
    module HoverProvider
      module SingletonMethods
        def content_for(service:, path:, line:, column:)
          project = service.project

          case (target = project.targets_for_path(path))
          when Project::Target
            Ruby.new(service: service).content_for(target: target, path: path, line: line, column: column)
          when Array
            RBS.new(service: service).content_for(target: target[0], path: path, line: line, column: column)
          end
        end
      end

      extend SingletonMethods
    end
  end
end
