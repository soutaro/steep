module Steep
  module AnnotationsHelper
    module_function

    def deprecated_annotation?(annotations)
      annotations.reverse_each do |annotation|
        if match = annotation.string.match(/deprecated(:\s*(?<message>.+))?/)
          return [annotation, match[:message]]
        end
        if match = annotation.string.match(/steep:deprecated(:\s*(?<message>.+))?/)
          return [annotation, match[:message]]
        end
      end

      nil
    end
  end
end
