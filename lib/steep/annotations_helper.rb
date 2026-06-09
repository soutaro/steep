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

    def warning_annotation?(annotations)
      annotations.reverse_each do |annotation|
        if match = annotation.string.match(/\Awarning(:\s*(?<message>.+))?\z/)
          return [annotation, match[:message]]
        end
        if match = annotation.string.match(/\Asteep:warning(:\s*(?<message>.+))?\z/)
          return [annotation, match[:message]]
        end
      end

      nil
    end

    def type_name_annotations(type_name, env)
      case
      when type_name.class?
        case
        when decl = env.class_decls.fetch(type_name, nil)
          decl.each_decl.flat_map do |decl|
            if decl.is_a?(RBS::AST::Declarations::Base)
              decl.annotations
            else
              []
            end
          end
        when decl = env.class_alias_decls.fetch(type_name, nil)
          if decl.decl.is_a?(RBS::AST::Declarations::Base)
            decl.decl.annotations
          else
            [] #: Array[RBS::AST::Annotation]
          end
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
    end

    def deprecated_type_name?(type_name, env)
      if annotations = type_name_annotations(type_name, env)
        deprecated_annotation?(annotations)
      end
    end

    def warning_type_name?(type_name, env)
      if annotations = type_name_annotations(type_name, env)
        warning_annotation?(annotations)
      end
    end
  end
end
