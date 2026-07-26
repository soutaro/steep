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

      # `@type self_method: Klass#method` — like `SelfType` (binds `self` to an
      # instance of `Klass`) but ALSO names a method whose entry facts apply to
      # this top-level body. Used for a body checked outside a `def` that at
      # runtime IS a method (an ERB view template compiled to a method): the
      # annotation carries the `Klass#method` identity so the method-entry-fact
      # machinery can narrow reads in it, without physically wrapping the source
      # in a `def` (which would shift line positions).
      class SelfMethod
        include Located

        attr_reader :type
        attr_reader :method_name

        def initialize(type:, method_name:, location: nil)
          @type = type
          @method_name = method_name
          @location = location
        end

        def ==(other)
          other.is_a?(self.class) && other.type == type && other.method_name == method_name
        end
      end
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
