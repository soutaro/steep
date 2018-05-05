module Steep
  module AST
    module Annotation
      class Collection
        attr_reader :var_types
        attr_reader :method_types
        attr_reader :annotations
        attr_reader :block_type
        attr_reader :return_type
        attr_reader :self_type
        attr_reader :const_types
        attr_reader :instance_type
        attr_reader :module_type
        attr_reader :implement_module
        attr_reader :ivar_types
        attr_reader :dynamics
        attr_reader :break_type

        def initialize(annotations:)
          @var_types = {}
          @method_types = {}
          @const_types = {}
          @ivar_types = {}
          @dynamics = {}
          @break_type = nil

          annotations.each do |annotation|
            case annotation
            when VarType
              var_types[annotation.name] = annotation
            when MethodType
              method_types[annotation.name] = annotation
            when BlockType
              @block_type = annotation.type
            when ReturnType
              @return_type = annotation.type
            when SelfType
              @self_type = annotation.type
            when ConstType
              @const_types[annotation.name] = annotation.type
            when InstanceType
              @instance_type = annotation.type
            when ModuleType
              @module_type = annotation.type
            when Implements
              @implement_module = annotation
            when IvarType
              ivar_types[annotation.name] = annotation.type
            when Dynamic
              dynamics[annotation.name] = annotation
            when BreakType
              @break_type = annotation.type
            else
              raise "Unexpected annotation: #{annotation.inspect}"
            end
          end

          @annotations = annotations
        end

        def lookup_var_type(name)
          var_types[name]&.type
        end

        def lookup_method_type(name)
          method_types[name]&.type
        end

        def lookup_const_type(node)
          const_types[node]
        end

        def +(other)
          self.class.new(annotations: annotations.reject {|a| a.is_a?(BlockType) } + other.annotations)
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
