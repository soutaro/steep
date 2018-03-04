module Steep
  module AST
    module Signature
      class Gvar
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
