module Steep
  module AST
    module Signature
      module Members
        class Include
          attr_reader :location
          attr_reader :name
          attr_reader :args

          def initialize(location:, name:, args:)
            @location = location
            @name = name
            @args = args
          end
        end

        class Extend
          attr_reader :location
          attr_reader :name
          attr_reader :args

          def initialize(location:, name:, args:)
            @location = location
            @name = name
            @args = args
          end
        end

        class Method
          attr_reader :location
          attr_reader :name
          attr_reader :kind
          attr_reader :types
          attr_reader :attributes

          def initialize(location:, name:, kind:, types:, attributes:)
            @location = location
            @name = name
            @kind = kind
            @types = types
            @attributes = attributes
          end

          def module_method?
            kind == :module || kind == :module_instance
          end

          def instance_method?
            kind == :instance || kind == :module_instance
          end

          def constructor?
            attributes.include?(:constructor)
          end
        end

        class Ivar
          attr_reader :location
          attr_reader :name
          attr_reader :type

          def initialize(location:, name:, type:)
            @location = location
            @name = name
            @type = type
          end
        end
      end
    end
  end
end
