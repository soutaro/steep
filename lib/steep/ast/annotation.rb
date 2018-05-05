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
        attr_reader :location

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
      class BreakType < Typed; end

      class MethodType < Named; end
      class VarType < Named; end
      class ConstType < Named; end
      class IvarType < Named; end

      class Implements
        class Module
          attr_reader :name
          attr_reader :args

          def initialize(name:, args:)
            @name = name
            @args = args
          end

          def ==(other)
            other.is_a?(Module) && other.name == name && other.args == args
          end

          alias eql? ==

          def hash
            self.class.hash ^ name.hash ^ args.hash
          end
        end

        attr_reader :location
        attr_reader :name

        def initialize(name:, location:)
          @location = location
          @name = name
        end

        def ==(other)
          other.is_a?(Implements) &&
            other.name == name &&
            other.location == location
        end
      end

      class Dynamic
        attr_reader :location
        attr_reader :kind
        attr_reader :name

        def initialize(name:, location: nil, kind:)
          @location = location
          @name = name
          @kind = kind
        end

        def ==(other)
          other.is_a?(Dynamic) &&
            other.name == name &&
            (!other.location || location || other.location == location) &&
            other.kind == kind
        end

        def instance_method?
          kind == :instance || kind == :module_instance
        end

        def module_method?
          kind == :module || kind == :module_instance
        end
      end
    end
  end
end
