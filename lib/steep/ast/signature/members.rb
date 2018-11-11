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

          def incompatible?
            attributes.include?(:incompatible)
          end

          def private?
            attributes.include?(:private)
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

        class Attr
          attr_reader :location
          attr_reader :kind
          attr_reader :name
          attr_reader :ivar
          attr_reader :type

          def initialize(location:, kind:, name:, ivar:, type:)
            @location = location
            @kind = kind
            @name = name
            @ivar = ivar
            @type = type
          end

          def reader?
            kind == :reader
          end

          def accessor?
            kind == :accessor
          end
        end

        class MethodAlias
          attr_reader :location
          attr_reader :new_name
          attr_reader :original_name

          def initialize(location:, new_name:, original_name:)
            @location = location
            @new_name = new_name
            @original_name = original_name
          end
        end
      end
    end
  end
end
