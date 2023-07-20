module Steep
  module AST
    module Annotation
      class Collection
        attr_reader :annotations
        attr_reader :factory
        attr_reader :context

        attr_reader :var_type_annotations
        attr_reader :const_type_annotations
        attr_reader :ivar_type_annotations
        attr_reader :method_type_annotations
        attr_reader :block_type_annotation
        attr_reader :return_type_annotation
        attr_reader :self_type_annotation
        attr_reader :instance_type_annotation
        attr_reader :module_type_annotation
        attr_reader :implement_module_annotation
        attr_reader :dynamic_annotations
        attr_reader :break_type_annotation

        def initialize(annotations:, factory:, context:)
          @annotations = annotations
          @factory = factory
          @context = context

          @var_type_annotations = {}
          @method_type_annotations = {}
          @const_type_annotations = {}
          @ivar_type_annotations = {}
          @dynamic_annotations = []

          annotations.each do |annotation|
            case annotation
            when VarType
              var_type_annotations[annotation.name] = annotation
            when MethodType
              method_type_annotations[annotation.name] = annotation
            when BlockType
              @block_type_annotation = annotation
            when ReturnType
              @return_type_annotation = annotation
            when SelfType
              @self_type_annotation = annotation
            when ConstType
              @const_type_annotations[annotation.name] = annotation
            when InstanceType
              @instance_type_annotation = annotation
            when ModuleType
              @module_type_annotation = annotation
            when Implements
              @implement_module_annotation = annotation
            when IvarType
              @ivar_type_annotations[annotation.name] = annotation
            when Dynamic
              @dynamic_annotations << annotation
            when BreakType
              @break_type_annotation = annotation
            else
              raise "Unexpected annotation: #{annotation.inspect}"
            end
          end
        end

        def absolute_type(type)
          if type
            factory.absolute_type(type, context: context)
          end
        end

        def var_type(lvar: nil, ivar: nil, const: nil)
          case
          when lvar
            absolute_type(var_type_annotations[lvar]&.type)
          when ivar
            absolute_type(ivar_type_annotations[ivar]&.type)
          when const
            absolute_type(const_type_annotations[const]&.type)
          end
        end

        def method_type(name)
          if (a = method_type_annotations[name])
            a.type.map_type {|type| absolute_type(type) }
          end
        end

        def block_type
          absolute_type(block_type_annotation&.type)
        end

        def return_type
          absolute_type(return_type_annotation&.type)
        end

        def self_type
          absolute_type(self_type_annotation&.type)
        end

        def instance_type
          absolute_type(instance_type_annotation&.type)
        end

        def module_type
          absolute_type(module_type_annotation&.type)
        end

        def break_type
          absolute_type(break_type_annotation&.type)
        end

        def lvar_types
          var_type_annotations.each_key.with_object({}) do |name, hash| #$ Hash[Symbol, Types::t]
            hash[name] = var_type(lvar: name) || raise
          end
        end

        def ivar_types
          ivar_type_annotations.each_key.with_object({}) do |name, hash| #$ Hash[Symbol, Types::t]
            hash[name] = var_type(ivar: name) || raise
          end
        end

        def const_types
          const_type_annotations.each_key.with_object({}) do |name, hash| #$ Hash[RBS::TypeName, Types::t]
            hash[name] = var_type(const: name) || raise
          end
        end

        def instance_dynamics
          dynamic_annotations.flat_map do |annot|
            annot.names.select(&:instance_method?).map(&:name)
          end
        end

        def module_dynamics
          dynamic_annotations.flat_map do |annot|
            annot.names.select(&:module_method?).map(&:name)
          end
        end

        def merge_block_annotations(annotations)
          if annotations.context != context || annotations.factory != factory
            raise "Cannot merge another annotation: self=#{self}, other=#{annotations}"
          end

          retained_annotations = self.annotations.reject do |annotation|
            annotation.is_a?(BlockType) || annotation.is_a?(BreakType)
          end

          self.class.new(
            annotations: retained_annotations + annotations.annotations,
            factory: factory,
            context: context
          )
        end

        def any?(&block)
          annotations.any?(&block)
        end

        def size
          annotations.size
        end

        def include?(obj)
          annotations.include?(obj)
        end
      end
    end
  end
end
