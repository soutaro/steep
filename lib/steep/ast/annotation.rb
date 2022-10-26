module Steep
  module AST
    module Annotation
      module Located
        attr_reader :location

        def line
          location&.start_line
        end
      end

      class Named
        include Located

        attr_reader :name
        attr_reader :type

        def initialize(name:, type:, location: nil)
          @name = name
          @type = type
          @location = location
        end

        def ==(other)
          other.is_a?(self.class) &&
            other.name == name &&
            other.type == type
        end
      end

      class Typed
        include Located

        attr_reader :type

        def initialize(type:, location: nil)
          @type = type
          @location = location
        end

        def ==(other)
          other.is_a?(self.class) &&
            other.type == type
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

        include Located

        attr_reader :name

        def initialize(name:, location: nil)
          @location = location
          @name = name
        end

        def ==(other)
          other.is_a?(Implements) && other.name == name
        end
      end

      class Dynamic
        class Name
          attr_reader :kind
          attr_reader :name
          attr_reader :location

          def initialize(name:, kind:, location: nil)
            @name = name
            @kind = kind
            @location = location
          end

          def instance_method?
            kind == :instance || kind == :module_instance
          end

          def module_method?
            kind == :module || kind == :module_instance
          end

          def ==(other)
            other.is_a?(Name) &&
              other.name == name &&
              other.kind == kind
          end
        end

        include Located

        attr_reader :names

        def initialize(names:, location: nil)
          @location = location
          @names = names
        end

        def ==(other)
          other.is_a?(Dynamic) &&
            other.names == names
        end
      end
    end
  end
end
