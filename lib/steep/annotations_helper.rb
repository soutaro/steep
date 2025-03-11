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

    def deprecated_type_name?(type_name, env)
      annotations =
        case
        when type_name.class?
          case
          when decl = env.class_decls.fetch(type_name, nil)
            decl.decls.flat_map { _1.decl.annotations }
          when decl = env.class_alias_decls.fetch(type_name, nil)
            decl.decl.annotations
          end
        when type_name.interface?
          if decl = env.interface_decls.fetch(type_name, nil)
            decl.decl.annotations
          end
        when type_name.alias?
          if decl = env.type_alias_decls.fetch(type_name, nil)
            decl.decl.annotations
          end
        end

      if annotations
        deprecated_annotation?(annotations)
      end
    end
  end
end
