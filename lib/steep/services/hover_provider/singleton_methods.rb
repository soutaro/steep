module Steep
  module Services
    module HoverProvider
      module SingletonMethods
        def content_for(service:, path:, line:, column:)
          project = service.project
          target_for_code, targets_for_sigs = project.targets_for_path(path)

          case
          when target_for_code
            Ruby.new(service: service).content_for(target: target_for_code, path: path, line: line, column: column)
          when target = targets_for_sigs.first
            RBS.new(service: service).content_for(target: target, path: path, line: line, column: column)
          end
        end
      end

      extend SingletonMethods
    end
  end
end
