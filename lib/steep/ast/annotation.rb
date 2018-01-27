module Steep
  module AST
    module Annotation
      class Named
        attr_reader :name
        attr_reader :type
        attr_reader :location

        def initialize(name:, type:, location: nil)
          @name = name
          @type = type
          @location = location
        end

        def ==(other)
          other.is_a?(self.class) &&
            other.name == name &&
            other.type == type &&
            (!other.location || !location || other.location == location)
        end
      end

      class Typed
        attr_reader :type
        attr_reader :annotation

        def initialize(type:, location: nil)
          @type = type
          @location = location
        end

        def ==(other)
          other.is_a?(self.class) &&
            other.type == type &&
            (!other.location || !location || other.location == location)
        end
      end

      class ReturnType < Typed; end
      class BlockType < Typed; end
      class SelfType < Typed; end
      class InstanceType < Typed; end
      class ModuleType < Typed; end

      class MethodType < Named; end
      class VarType < Named; end
      class ConstType < Named; end
      class IvarType < Named; end

      class Implements
        attr_reader :location
        attr_reader :module_name

        def initialize(module_name:, location:)
          @location = location
          @module_name = module_name
        end

        def ==(other)
          other.is_a?(Implements) &&
            other.module_name == module_name &&
            other.location == location
        end
      end

      class Dynamic
        attr_reader :location
        attr_reader :name

        def initialize(name:, location:)
          @location = location
          @name = name
        end

        def ==(other)
          other.is_a?(Dynamic) &&
            other.name == name &&
            other.location == location
        end
      end
    end
  end
end
