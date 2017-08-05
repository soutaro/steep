module Steep
  module Signature
    module Members
      class InstanceMethod
        attr_reader :name
        attr_reader :types

        def initialize(name:, types:)
          @name = name
          @types = types
        end

        def ==(other)
          other.is_a?(InstanceMethod) && other.name == name && other.types == types
        end
      end

      class ModuleMethod
        attr_reader :name
        attr_reader :types

        def initialize(name:, types:)
          @name = name
          @types = types
        end

        def ==(other)
          other.is_a?(ModuleMethod) && other.name == name && other.types == types
        end
      end

      class ModuleInstanceMethod
        attr_reader :name
        attr_reader :types

        def initialize(name:, types:)
          @name = name
          @types = types
        end

        def ==(other)
          other.is_a?(ModuleInstanceMethod) && other.name == name && other.types == types
        end
      end

      class Include
        attr_reader :name

        def initialize(name:)
          @name = name
        end

        def ==(other)
          other.is_a?(Include) && other.name == name
        end
      end

      class Extend
        attr_reader :name

        def initialize(name:)
          @name = name
        end

        def ==(other)
          other.is_a?(Extend) && other.name == name
        end
      end
    end

    class Module
      attr_reader :name
      attr_reader :params
      attr_reader :members

      def initialize(name:, params:, members:)
        @name = name
        @members = members
        @params = params
      end

      def ==(other)
        other.is_a?(Module) && other.name == name && other.params == params && other.members == members
      end

      def to_interface(this:, params:, kind:)

      end
    end

    class Class
      attr_reader :name
      attr_reader :params
      attr_reader :members
      attr_reader :super_class

      def initialize(name:, params:, members:, super_class:)
        @name = name
        @members = members
        @params = params
        @super_class = super_class
      end

      def ==(other)
        other.is_a?(Class) && other.name == name && other.params == params && other.members == members && other.super_class == super_class
      end

      def to_interface(this:, params:, kind:)

      end
    end
  end
end
