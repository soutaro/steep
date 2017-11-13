module Steep
  module AST
    module Signature
      class Interface
        class Method
          attr_reader :location
          attr_reader :name
          attr_reader :types

          def initialize(location:, name:, types:)
            @location = location
            @name = name
            @types = types
          end
        end

        attr_reader :location
        attr_reader :name
        attr_reader :params
        attr_reader :methods

        def initialize(location:, name:, params:, methods:)
          @location = location
          @name = name
          @params = params
          @methods = methods
        end
      end
    end
  end
end
